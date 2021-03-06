################################################################################
#                                                                              #
# This script contains functions that perform calculations on the data used    #
# or produced in the simulations.                                              #
#                                                                              #
# ABM developed by Florian Schiel and Jonathan Harrington                      #
# Adapted by Johanna Cronenberg and Michele Gubian                             #
#                                                                              #
# Copyright 2020, Institute of Phonetics and Speech Processing, LMU Munich.    #
#                                                                              #
################################################################################

is_cache_valid <- function(agent, cacheName) {
  agent$cache[name == cacheName, valid]
}

update_cache <- function(agent, cacheName, method, ...) {
  agent$cache[name == cacheName, `:=`(value = list(method(agent, ...)), valid = TRUE)]
}

get_cache_value <- function(agent, cacheName) {
  agent$cache[name == cacheName, value][[1]]
}

invalidate_cache <- function(agent, cacheName) {
  agent$cache[name == cacheName, valid := FALSE]
}

compute_qda <- function(agent) {
  # execute the QDA (Quadrativ Discriminant Analysis)
  # a wrapper for qda()
  qda(as.matrix(agent$features)[agent$labels$valid == TRUE, , drop = FALSE],
      grouping = agent$labels$label[agent$labels$valid == TRUE])
}

compute_posterior_probabilities <- function(agent, token, method) {
  if (method == "qda") {
    # no other option at the moment
    if (!is_cache_valid(agent, "qda")) {
      update_cache(agent, "qda", compute_qda)
      # cacheMissCounter <<- cacheMissCounter + 1
    }
    predict(get_cache_value(agent, "qda"), token$features)$posterior
  } else {
    NULL
  }
}

recognize_posterior_probabilities <- function(posteriorProb, label, method, ...) {
  if (method == "maxPosteriorProb") {
    colnames(posteriorProb)[which.max(posteriorProb)] == label
  } else if (method == "posteriorProbThr") {
    posteriorProb[, label] >= list(...)[["posteriorProbThr"]]
  }
}

compute_mahal_distance <- function(agent, token, label, method = NULL) {
  if (is.null(method)) {
    # no other option at the moment
    # a wrapper to mahalanobis()
    mahalanobis(token$features,
                apply(as.matrix(agent$features)[agent$labels$valid == TRUE & 
                                                      agent$labels$label == label, , drop = FALSE], 2, mean),
                cov(as.matrix(agent$features)[agent$labels$valid == TRUE & 
                                                    agent$labels$label == label, , drop = FALSE]))
    
  }
}

convert_pop_list_to_dt <- function(pop, extraCols = list(condition = "x")) {
  # This function converts the population list into a data.table.
  # Function call in simulations.R, save_population().
  #
  # Args:
  #    - pop: population list
  #    - extraCols: a list of columns that will be added to the pop data.table
  #      Default: list(condition = "x")
  #
  # Returns:
  #    - the population as a data.table
  #
  
  # loop over the lists in pop
  rbindlist(lapply(seq_along(pop), function (i) {
    # the next four lines join the 'feature' columns, the 'labels' columns, 
    # and the 'initial' columns, for the current agent (pop[[i]])
    cbind(pop[[i]]$features, pop[[i]]$labels) %>%
      .[valid == TRUE] %>%
      inner_join(pop[[i]]$initial, by = 'word') %>%
      setDT %>%
      # the next four lines set agentID, speaker, group, equivalence for the current agent
      .[, `:=`(agentID = pop[[i]]$agentID,
               speaker = pop[[i]]$speaker,
               group = pop[[i]]$group)] %>%
      .[, equivalence := equal_class(initial, label)]
  })) %>% {
    # add every item from extraCols as a column to new pop data.table
    for (col in names(extraCols)) {
      .[, (col) := extraCols[[col]]]
    }
    .[]
  }
}

knearest_fallback <- function(points, extendedIndices, targetIndices, K) {
  # This is an auxiliary function mainly used by SMOTE.
  # SMOTE needs to identify K nearest neighbours each time it produces an extra token. 
  # That means it needs minimum K+1 tokens being available in total, i.e. one target + K neighbours.
  # 'points' is a large set of tokens (rows), typically belonging to one phoneme,
  # from which targetIndices identify the tokens that should be used by SMOTE, typically belonging to a word.
  # If the number of targetIndices < K, additional fallback tokens (rows) are selected from 'points'.
  # These additional tokens are chosen amongst the K + 1 nearest neighbours of points[targetIndices]. 
  
  # Function call in interactions.R, produce_token().
  #
  # Args:
  #    - points: matrix of feature values
  #    - targetIndices: list of indices
  #    - K: number of nearest neighbors
  #
  # Returns:
  #    - list of targetIndices and fallback:
  #
  
  if (any(c(targetIndices, extendedIndices) < 0)) {
    stop("knearest_fallback: negative index notation not supported for targetIndices and extendedIndices")
  }
  if (nrow(points) == 0) {
    # print to LOG 
    return (NULL)
  }
  if (K <= 0) {
    stop(paste("knearest_fallback: invalid number of nearest neighbours requested: K =", K))
  }
  # Stop if extendedIndices are not in points rows indices
  # note: all(NULL %in% something) == TRUE, hence does not stop when extendedIndices == NULL
  if (!all(extendedIndices %in% seq_len(nrow(points)))) {
    stop("knearest_fallback: extendedIndices out of bound")
  }
  if (length(targetIndices) <= 0) {
    stop("knearest_fallback: empty targetIndices")
  }
  # when no extendedIndices provided, just return targetIndices
  if (is.null(extendedIndices) | length(extendedIndices) == 0) {
    return(targetIndices)
  }
  # Stop if targetIndices are not part of (non-empty) extendedIndices 
  if (!all(targetIndices %in% extendedIndices)) {
    stop("knearest_fallback: targetIndices out of bound")
  }
  # Fringe case: return extendedIndices when K + 1 > length(extendedIndices)
  if (K + 1 > length(extendedIndices)) {
    # print to LOG
    return(extendedIndices)
  }
  
  # compute number of tokens to be sampled
  nFallback <- K + 1 - length(targetIndices)
  
  # if it turns out that there are enough tokens in targetIndices, return them
  if (nFallback <= 0) {
    return(targetIndices)
  }
  
  # apply a K nearest neighbor algorithm on the points,
  # and sample as many as nFallback tokens from the unique neighbors 
  # that are not equal to the targetIndices
  fallbackIndices <- knnx.index(points[extendedIndices, , drop=FALSE], points[targetIndices, , drop=FALSE], K + 1) %>%
    as.vector %>%
    extendedIndices[.] %>%
    setdiff(targetIndices) %>%
    sample(nFallback)
    
  return(c(targetIndices, fallbackIndices))
}

equal_class <- function(orig, derived) {
  # This function generates equivalence labels from the initial and 
  # developed labels of the agents in the population.
  # Function call in calculations.R, convert_pop_list_to_dt().
  #
  # Args:
  #    - orig: a vector of characters from pop[[i]]$initial$initial
  #    - derived: a vector of characters from pop[[i]]$labels$label
  #
  # Returns:
  #    - derived: the equivalence label
  #
  
  tab <- t(table(orig, derived))
  namesOfOrig <- colnames(tab)
  # namesOfOrig <- namesOfOrig[order(nchar(namesOfOrig), namesOfOrig)]
  namesOfDerived <- rownames(tab)
  # namesOfDerived <- namesOfDerived[order(nchar(namesOfDerived), namesOfDerived)]
  bintab <- matrix(FALSE, nrow = nrow(tab), ncol = ncol(tab))
  for (j in 1:ncol(tab)) {
    bintab[,j] <- tab[,j] != 0
  }
  for (j in 1:nrow(bintab)) {
    lab.equivalent <- paste(namesOfOrig[bintab[j, ]], collapse="+")
    derived[derived == namesOfDerived[j]] <- lab.equivalent
  }
  return(derived)
}

