################################################################################
# OpenMx code for Model 1 
# (ACE Model, baseline twins, residualized for age and sex)
#
# Diana Smith
# Aug 2022
#################################################################################

rm(list=ls())

# # Load Libraries & Options
library(OpenMx)
library(R.matlab)

# set paths and source code
setwd("/home/d9smith/projects/behav_genet_2022")
source("miFunctions2.R")
source("twin_functions.R")

# Set path to directory where results will be saved
outpath = "/space/syn50/1/data/ABCD/d9smith/random_effects/behavioral/results/results_20220901"
mxOption(NULL, "Default optimizer", 'SLSQP') # Using default optimizer for OpenMx

# Define the path to tge cmig_tools_utils/r directory
# Note: cmig_tools is available at: https://github.com/cmig-research-group/cmig_tools
funcpath <- '/home/d9smith/github/cmig_tools/cmig_tools_utils/r'
source(paste0(funcpath, '/', 'loadtxt.R'))

# Define paths to data files
twin_file = "/home/d9smith/projects/random_effects/behavioral/twinfiles/twin_IDs_complete.txt"
pheno_file = "/space/syn50/1/data/ABCD/d9smith/random_effects/behavioral/data/pheno/baseline_twins_res_agesex.txt"

zyg_file = "/home/d9smith/projects/random_effects/behavioral/twinfiles/ABCD_twins_all.txt"
grm_file = "/home/d9smith/projects/random_effects/behavioral/twinfiles/twins_measured_grm.txt"

# Load data
twin = read.table(twin_file, header = T, sep = "\t")
grm = read.table(grm_file,header = TRUE,sep=",")

twin <- merge(twin, grm, by=c("IID1","IID2"))
twin_complete = twin[twin$IID1_complete==TRUE & twin$IID2_complete==TRUE,]
twin_complete = twin_complete[,c("IID1","IID2","twin1_genetic_zygosity","measured_grm")]

pheno = read.table(pheno_file, header = TRUE, sep = "\t")
pheno1 = pheno
pheno2 = pheno
names(pheno1)[-(1:2)] = paste0(names(pheno)[-(1:2)],1)
names(pheno2)[-(1:2)] = paste0(names(pheno)[-(1:2)],2)

df = merge(twin_complete, pheno2, by.x=c("IID2"), by.y=c("src_subject_id"))
df = merge(df, pheno1, by.x=c("IID1", "eventname"), by.y=c("src_subject_id", "eventname"))

# Note from DS 2022-10-06:
# The resulting dataframe "df" contains 699 twin pairs, all with complete data for each twin. 
# 399 DZ twin pairs, 300 MZ twin pairs.

# Monozygotic coded as 1, Dizygotic coded as 2
df$zyg = NA
df[df$twin1_genetic_zygosity=="Monozygotic",]$zyg = 1
df[df$twin1_genetic_zygosity=="Dizygotic",]$zyg = 2

if (0){
df[df$twin1_genetic_zygosity=="Monozygotic",]$measured_grm = 1
df[df$twin1_genetic_zygosity=="Dizygotic",]$measured_grm = 0.5

}

# Write function for ACE Model
estHerit <- function(data, task, measured_grm=FALSE){
  nt        <- 2                         # number of individuals
  nv        <- 1                         # number of variables
  ntv       <- nv*nt                     # number of total variables
  selVars   <- paste(task,c(rep(1,nv),rep(2,nv)),sep="")

  # Select Data for Analysis
  mzData    <- subset(data, zyg==1, selVars)
  dzData    <- subset(data, zyg==2, selVars)
  nl        <- subset(data, select=c('measured_grm', selVars))

  if (measured_grm == TRUE) {

    # Set Starting Values
    sMu      <- 0                        # start value for means
    sVa      <- .2                       # start value for A
    sVc      <- .2                       # start value for C
    sVe      <- .6                       # start value for E

    # ----------------------------------------------------------------------------------------------------------------------
    # PREPARE MODEL

    # Create Algebra for expected Mean Matrices
    intercept     <- mxMatrix( type="Full", nrow=1, ncol=ntv, free=TRUE, values=sMu, labels=task, name="intercept" )
    expMean       <- mxAlgebra(expression = intercept, name="expMean" )

    # Create Matrices for Variance Components
    covA      <- mxMatrix( type="Symm", nrow=nv, ncol=nv, free=TRUE, values=sVa, label="VA11", name="A" ) 
    covC      <- mxMatrix( type="Symm", nrow=nv, ncol=nv, free=TRUE, values=sVc, label="VC11", name="C" )
    covE      <- mxMatrix( type="Symm", nrow=nv, ncol=nv, free=TRUE, values=sVe, label="VE11", name="E" )

    # Create Algebra for expected Variance/Covariance Matrices in MZ & DZ twins
    covP      <- mxAlgebra( expression= A+C+E, name="V" )
    relA      <- mxMatrix( type="Stand", nrow=nt, ncol=nt, free=FALSE, labels="measured_grm", name="rA" ) 
    relC      <- mxMatrix( type="Unit", nrow=nt, ncol=nt, free=FALSE, name="rC" ) 
    relE      <- mxMatrix( type="Iden", nrow=nt, ncol=nt, free=FALSE, name="rE" ) 

    expCov   <- mxAlgebra( expression= rA%x%A + rC%x%C + rE%x%E, name="expCov" )

    # Create Data Objects for Multiple Groups
    dataTW    <- mxData( observed=nl, type="raw" )

    # Create Expectation Objects for Multiple Groups
    expTW     <- mxExpectationNormal(covariance="expCov", means="intercept", dimnames=selVars )
    funML     <- mxFitFunctionML()

    # Create Model Objects for Multiple Groups
    # defs      <- list(defAge, defSex, relA)
    # pars      <- list( intercept, betaS, betaA, covA, covC, covE, covP, relC, relE)
    defs      <- list(relA)
    pars      <- list(intercept, covA, covC, covE, covP, relC, relE)

    # Create Algebra for Variance Components
    rowVC     <- rep('VC',nv)
    colVC     <- rep(c('A','C','E','SA','SC','SE'),each=nv)
    estVC     <- mxAlgebra( expression=cbind(A,C,E,A/V,C/V,E/V), name="VC", dimnames=list(rowVC,colVC) )

    # Create Confidence Interval Objects
    ciACE     <- mxCI( "VC[1,1:6]" )

    # Build Model with Confidence Intervals
    modelACE   <- mxModel( "oneACEc", defs, pars, expMean, expCov, dataTW, expTW, funML, estVC, ciACE )

} else {
    # Set Starting Values
    svMe      <- rnorm(1)                       # start value for means
    svPa      <- .4                        # start value for path coefficient
    svPe      <- .6                        # start value for path coefficient for e
    lbPa      <- .0001      
    # ACE Model
    # Create Algebra for expected Mean Matrices
    meanG     <- mxMatrix( type="Full", nrow=1, ncol=ntv, free=TRUE, values=svMe, labels=task, name="meanG" )

    # Create Matrices for Path Coefficients
    pathA     <- mxMatrix( type="Lower", nrow=nv, ncol=nv, free=TRUE, values=svPa, label="a11", lbound=lbPa, name="a" ) 
    pathC     <- mxMatrix( type="Lower", nrow=nv, ncol=nv, free=TRUE, values=svPa, label="c11", lbound=lbPa, name="c" )
    pathE     <- mxMatrix( type="Lower", nrow=nv, ncol=nv, free=TRUE, values=svPe, label="e11", lbound=lbPa, name="e" )

    # Create Algebra for Variance Components
    covA      <- mxAlgebra( expression=a %*% t(a), name="A" )
    covC      <- mxAlgebra( expression=c %*% t(c), name="C" ) 
    covE      <- mxAlgebra( expression=e %*% t(e), name="E" )

    # Create Algebra for expected Variance/Covariance Matrices in MZ & DZ twins
    covP      <- mxAlgebra( expression= A+C+E, name="V" )
    covMZ     <- mxAlgebra( expression= A+C, name="cMZ" )
    covDZ     <- mxAlgebra( expression= 0.5%x%A+ C, name="cDZ" )
    expCovMZ  <- mxAlgebra( expression= rbind( cbind(V, cMZ), cbind(t(cMZ), V)), name="expCovMZ" )
    expCovDZ  <- mxAlgebra( expression= rbind( cbind(V, cDZ), cbind(t(cDZ), V)), name="expCovDZ" )

    # Create Data Objects for Multiple Groups
    dataMZ    <- mxData( observed=mzData, type="raw" )
    dataDZ    <- mxData( observed=dzData, type="raw" )

    # Create Expectation Objects for Multiple Groups
    expMZ     <- mxExpectationNormal( covariance="expCovMZ", means="meanG", dimnames=selVars )
    expDZ     <- mxExpectationNormal( covariance="expCovDZ", means="meanG", dimnames=selVars )
    funML     <- mxFitFunctionML()

    # Create Model Objects for Multiple Groups
    pars      <- list(meanG, pathA, pathC, pathE, covA, covC, covE, covP)
    modelMZ   <- mxModel( name="MZ", pars, covMZ, expCovMZ, dataMZ, expMZ, funML )
    modelDZ   <- mxModel( name="DZ", pars, covDZ, expCovDZ, dataDZ, expDZ, funML )
    multi     <- mxFitFunctionMultigroup( c("MZ","DZ") )

    # Create Algebra for Variance Components
    rowVC     <- rep('VC',nv)
    colVC     <- rep(c('A','C','E','SA','SC','SE', 'SV'),each=nv)
    estVC     <- mxAlgebra( expression=cbind(A,C,E,A/V,C/V,E/V,V), name="VC", dimnames=list(rowVC,colVC))

    # Create Confidence Interval Objects
    ciACE     <- mxCI( "VC[1,1:7]" )

    # Build Model with Confidence Intervals
    modelACE  <- mxModel( "oneACEc", pars, modelMZ, modelDZ, multi, estVC, ciACE )  
  }
  # ------------------------------------------------------------------------------
  # RUN MODEL

  # Run ACE Model
  fitACE    <- mxRun( modelACE, intervals=T )
  sumACE    <- summary( fitACE , verbose=T)

  # Falkoner 
  r_mz = cor(mzData, use='complete.obs')[paste0(task, '1'), paste0(task, '2')]
  r_dz = cor(dzData, use='complete.obs')[paste0(task, '1'), paste0(task, '2')]
#     print(paste0('Exit code status ', fitACE$output$status, ' status status ', fitACE$output$status))
  A <- mxEval(A, fitACE)
  C <- mxEval(C, fitACE)
  E <- mxEval(E, fitACE)

  V <- (A+C+E)   # total variance
  a2 <- A/V      # genetic term as proportion of total variance, i.e. standardized
  c2 <- C/V      # shared environment term as proportion of total variance
  e2 <- E/V      # nonshared environment term as proportion of total variance
  
  # Extract confidence intervals
  CI <- data.frame(
    A=sumACE$CIdetail[sumACE$CIdetail$parameter=='oneACEc.VC[1,4]', 'value'], 
    C=sumACE$CIdetail[sumACE$CIdetail$parameter=='oneACEc.VC[1,5]', 'value'], 
    E=sumACE$CIdetail[sumACE$CIdetail$parameter=='oneACEc.VC[1,6]', 'value'], 
    row.names=c('left', 'right')
  )
  
  c(a2=as.numeric(a2), 
    c2=as.numeric(c2),
    e2=as.numeric(e2),
    CI=CI,
    falkoner=2*(r_mz-r_dz), summary=sumACE)
}

estHerit(df, 'nihtbx_fluidcomp_uncorrected', measured_grm=FALSE)
estHerit(df, 'nihtbx_fluidcomp_uncorrected', measured_grm=TRUE)

estHerit(df, 'nihtbx_cryst_uncorrected', measured_grm=FALSE)
estHerit(df, 'nihtbx_cryst_uncorrected', measured_grm=TRUE)

# create data frames for parameter estimates
tasks = names(pheno)[-(1:2)]  

A <- data.frame(
  task=tasks
)
C <- data.frame(
  task=tasks
)
E <- data.frame(
  task=tasks
)

loglik <- data.frame(
  task=tasks
)

for (t in 1:length(tasks)){
  result = estHerit(df, tasks[t], measured_grm=FALSE)
  A[tasks==tasks[t], 'openmx'] = as.numeric(result$a2)
  A[tasks==tasks[t], 'openmx_ci_lower'] = result$CI.A[1]
  A[tasks==tasks[t], 'openmx_ci_upper'] = result$CI.A[2]
  # C compoenent
  C[tasks==tasks[t], 'openmx'] = as.numeric(result$c2)
  C[tasks==tasks[t], 'openmx_ci_lower'] = result$CI.C[1]
  C[tasks==tasks[t], 'openmx_ci_upper'] = result$CI.C[2]
  # E compoenent
  E[tasks==tasks[t], 'openmx'] = as.numeric(result$e2)
  E[tasks==tasks[t], 'openmx_ci_lower'] = result$CI.E[1]
  E[tasks==tasks[t], 'openmx_ci_upper'] = result$CI.E[2]

  # log likelihood
  loglik[tasks==tasks[t], 'openmx_loglik'] = result$summary.Minus2LogLikelihood / (-2)
}

# save estimates 
write.csv(A, paste(outpath, "openmx_A.csv", sep = "/"), row.names=F)
write.csv(C, paste(outpath, "openmx_C.csv", sep = "/"), row.names=F)
write.csv(E, paste(outpath, "openmx_E.csv", sep = "/"), row.names=F)
write.csv(loglik, paste(outpath, "openmx_loglik.csv", sep = "/"), row.names=F)
