################################################################################
#                                                                              #
# This script contains the following functions that perform calculations with  #
# the data:                                                                    #
#                                                                              #
# - convert_list_to_df(population, condition)                                  #
# - calc_rejection_ratio(population)                                           #
# - make_equivalence_labels(originalPopulation)                                #
# - equal_class(orig, derived)                                                 #
# - get_equivalence_clusters(population, eLabels, abmName, simulation)         #
# - reconstruct_tracks(df)                                                     #
# - inverse_dct(coeffs)                                                        #
#                                                                              #
# Developed by Florian Schiel and Jonathan Harrington                          #
# Adapted by Johanna Cronenberg                                                #
#                                                                              #
# Copyright 2018, Institute of Phonetics and Speech Processing, LMU Munich.    #
#                                                                              #
################################################################################


convert_list_to_df <- function(population, condition = "x") {
  # This function converts the population list into a dataframe with
  # the additional column condition.
  # Function call in coreABM.R.
  #
  # Args:
  #    - population: result of createPopulation(), defined in coreABM.R
  #    - condition: a string denoting the state of the ABM
  #
  # Returns:
  #    - df: a dataframe with columns word, age, speaker, group, initial, condition,
  #      and P1, P2, etc.
  #
  params <- NULL
  word <- NULL
  label <- NULL
  age <- NULL
  speaker <- NULL
  group <- NULL
  initial <- NULL
  
  for (j in 1:length(population)) {
    params <- rbind(params, population[[j]]$memory$P)
    word <- c(word, population[[j]]$memory$word)
    label <- c(label, population[[j]]$memory$label)
    age <- c(age, population[[j]]$memory$age)
    speaker <- c(speaker, population[[j]]$memory$speaker)
    group <- c(group, population[[j]]$memory$group)
    initial <- c(initial, population[[j]]$memory$initial)
  }
  
  cond <- rep(condition, nrow(params))
  df <- data.frame(params, word = factor(word), label = factor(label), age, speaker = factor(speaker), 
                   group = factor(group), initial = factor(initial), condition = factor(cond))
  names(df) <- c(paste("P", 1:ncol(params), sep = ""), "word", "label", "age", "speaker", "group", 
                 "initial", "condition")
  
  return(df)
}


calc_rejection_ratio <- function(population) {
  # This function computes the ratio of rejections, i.e. how many percent of
  # all produced tokens were rejected by the receiving agent.
  # Function call in coreABM.R.
  #
  # Args:
  #    - population: result of performInteractions(), defined in coreABM
  #
  # Returns:
  #    - numRejections/numTokens: quotient
  #
  numTokens <- 0
  numRejections <- 0
  for (i in 1:length(population)) {
    numTokens <- numTokens + length(population[[i]]$memory$update)
    numRejections <- numRejections + sum(population[[i]]$memory$update == "n")
  }
  return(numRejections/numTokens)
}


make_equivalence_labels <- function(originalPopulation) {
  # This function generates equivalence labels from the 
  # initial labels of the agents in the population.
  # Function call in coreABM.R.
  #
  # Args:
  #    - originalPopulation: data.frame generated from population (done in coreABM.R)
  #
  # Returns:
  #    - eLabels: a vector of equivalence labels
  #
  labelClasses <- unique(as.character(originalPopulation$initial))
  labelClasses <- labelClasses[order(labelClasses)]
  eLabels <- NULL
  for (i in 1:length(labelClasses)) {
    combi <- t(combn(labelClasses, i))
    eLabels <- c(eLabels, apply(combi, 1, function(x) {paste0(x, collapse="+")}))
  }
  return(eLabels)
}


equal_class <- function(orig, derived) {
  # This function generates equivalence labels from the initial and 
  # developed labels of the agents in the population.
  # Function call in coreABM.R.
  #
  # Args:
  #    - orig: a vector of characters; either originalPopulation$initial 
  #      or modifiedPopulation$initial
  #    - derived: a vector of characters; either originalPopulation$label
  #      or modifiedPopualtion$label
  #
  # Returns:
  #    - derived: the equivalence label
  #
  tab <- t(table(orig, derived))
  namesOfOrig <- colnames(tab)
  #namesOfOrig <- namesOfOrig[order(nchar(namesOfOrig), namesOfOrig)]
  namesOfDerived <- rownames(tab)
  #namesOfDerived <- namesOfDerived[order(nchar(namesOfDerived), namesOfDerived)]
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

get_equivalence_clusters <- function(population, eLabels, abmName, simulation) {
  # This function calculates in how many of the agents each
  # equivalence label occurs.
  # Function call in coreABM.R.
  #
  # Args:
  #    - population: either originalPopulation or modifiedPopulation, defined in coreABM.R
  #    - eLabels: vector equivalenceLabels, as defined in coreABM.R
  #    - abmName: variable defined in coreABM.R
  #    - simulation: variable nrOfSimulations, as defined in coreABM.R
  #
  # Returns:
  #    - df: a data.frame with columns ABM, simulation, and one column
  #      per equivalence label
  #
  frequencyCount <- plyr::count(population, c("speaker", "equivalence"))
  df <- as.data.frame.matrix(t(table(frequencyCount$equivalence)))
  for (label in equivalenceLabels) {
    if (!label %in% colnames(df)) {
      df <- cbind(df, newCol = 0)
      names(df)[names(df) == "newCol"] <- label
    }
  }
  df$ABM <- abmName
  df$simulation <- simulation
  df <- df[, c("ABM", "simulation", equivalenceLabels)]
  return(df)
}

reconstruct_tracks <- function(df) {
  # This function reconstructs tracks from DCT coefficients.
  # Function calls in plotting.R.
  #
  # Args:
  #    - df: a data.frame (at least) with columns P1, P2, P3 (or any other combination of 
  #      exactly three columns that begin with "P"), initial, label, word,
  #      speaker, age, group, condition, and equivalence; see the function calls in
  #      plotting.R to see the data.frames this function is used with
  #
  # Returns:
  #    - result: a list of two data.frames, one representing the mean
  #      reconstructed track values, the other representing the standard
  #      deviation of the track values
  #
  valueColumns <- grep("P", names(df), value = T)
  coeffs <- as.matrix(dplyr::select(df, valueColumns))
  
  #print("carrying out inverse dct")
  reconstructedTracks <- inverse_dct(coeffs)
  #print("done")
  
  track.df <- data.frame(track = reconstructedTracks, time = rep(seq(0, 1, length = 21), times = nrow(coeffs)),
                       initial = rep(as.character(df$initial), each = 21), label = rep(as.character(df$label), each = 21),
                       word = rep(as.character(df$word), each = 21), speaker = rep(as.character(df$speaker), each = 21),
                       group = rep(as.character(df$group), each = 21), age = rep(as.character(df$age), each = 21), 
                       condition = rep(as.character(df$condition), each = 21), equivalence = rep(as.character(df$equivalence), each = 21))
  meanTrack <- aggregate(track ~ time * initial + condition, mean, data = track.df)
  sdTrack <- aggregate(track ~ time * initial + condition, sd, data = track.df)
  sdTrack$upper <- meanTrack$track + 1.96 * sdTrack$track
  sdTrack$lower <- meanTrack$track - 1.96 * sdTrack$track
  
  result <- list(meanTrack, sdTrack)
  return(result)
}


inverse_dct <- function(coeffs) {
  # This function computes the inverse DCT of three DCT coefficients.
  # Function call in reconstruct_tracks() above.
  #
  # Args:
  #    - coeffs: a matrix of exactly three columns (e.g. P1, P2, P3).
  #
  # Returns:
  #    - result: a numeric vector with all the track values
  #
  result <- NULL
  matrixDimension <- ncol(coeffs) - 1
  for (i in 1:nrow(coeffs)) {
    currentRow <- as.numeric(coeffs[i, ])
    data <- transformedData <- c(currentRow, rep(0, times = 21 - length(currentRow)))
    m <- 1:matrixDimension
    for (n in 0:20) {
      transformedData[n + 1] <- (1/sqrt(2)) * data[1] * cos((pi * 0 * (2 * n + 1)) / (2 * 21)) + sum(data[m + 1] * cos((pi * m * (2 * n + 1))/(2 * 21)))
    }
    result <- c(result, transformedData)
  }
  return(result)
}
