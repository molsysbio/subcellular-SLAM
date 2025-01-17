#Arguments T2C mutation file (columns T, T2C, frequency), A2G mutation file (columns T, T2C, frequency), output file, threshold for exclusion of events in 1/%

library(dplyr)
library(readr)

mark.excluded.ks <- function(p.error,cutoff.mult,data){
                                        #contrib.error is the contribution of events from p.error multiplied by the cutoff threshold
                                        #exclude is TRUE if frequency of events from p.error > 1/cutoff x observed a_kn
    data$contrib.error=cutoff.mult*dbinom(x=data$k,size=data$N,prob=p.error)*data$sum.akn
    data$exclude=data$akn<data$contrib.error
    data
}


estimate.excluded.counts <- function(k,N,prob,sum.akn){
                                        # estimates counts for excluded events by multiplying the sum of all
                                        #non-excluded events by the binomial coeffecients generated by p.conv
    dbinom(x=k,size=N,prob=prob)/sum(dbinom(x=(max(k)+1):N,size=N,prob=prob))*sum.akn
}

replace.excluded.counts <- function(p.conv,data){
                                        # replaces excluded counts in the data by their estimates
    group_by(data,N) %>%
        mutate(akn=ifelse(exclude,estimate.excluded.counts(k[exclude],N[1],p.conv,sum(akn[!exclude])),akn))
}

ml.estimate.pconv <- function(data){
                                        # computes the ML estimate for p.conv
    k=data$k
    N=data$N
    akn=data$akn
    p=sum(k*akn)/sum(N*akn)
}    


em.algorithm.pconv <- function(prob.error,cutoff.mult,data){
                                        # Implements the EM algorithm for estimating p.conv
    d0=data
    ll=0
    rr=1
    while (abs(ll-rr)>1e-8){
        pi=(ll+rr)/2
        d0=replace.excluded.counts(pi,mark.excluded.ks(prob.error,cutoff.mult,d0))
        pi.plus.one=ml.estimate.pconv(d0)
        if (pi.plus.one < pi){
            rr=pi
        }else{
            ll=pi.plus.one
        }
    }
    excl <- mark.excluded.ks(prob.error,cutoff.mult,d0)
    data_frame(pr=pi,fract.included=sum(excl$akn[!excl$exclude])/sum(data$akn),no.included=sum(excl$akn[!excl$exclude]))
}

args = commandArgs(trailingOnly=TRUE)
file.t2c=args[1]
file.a2g=args[2]
out.file=args[3]
threshold.excluded.events=as.numeric(as.character(args[4]))


## file.t2c <- "frequencies_T2Ct45min2.tsv"
## file.a2g <- "frequencies_A2Gt45min2.tsv"
## threshold.excluded.events <- 100
## out.file <- "p_error_p_conv.csv"

data.a2g <- read_tsv(file.a2g,col_names=FALSE)
data.t2c <- read_tsv(file.t2c,col_names=FALSE)


data.a2g %>%
    mutate(all.T=X1*X3,all.T2C=X2*X3) %>%
    summarise(all.T=sum(all.T),all.T2C=sum(all.T2C)) %>%
    mutate(p.error=all.T2C/all.T) ->
    error.estimates


                                        # data for the em algorithm is supplied in the form
                                        # N (number of Ts in read), k (number of T2Cs in read),
                                        # akn (number of reads with N Ts and k T2Cs)

data.t2c %>%
    select(N=X1,k=X2,akn=X3) %>%
    group_by(N) %>%
    mutate(sum.akn=sum(akn)) %>%
    ungroup %>%
    em.algorithm.pconv(error.estimates$p.error,threshold.excluded.events,.) ->
    out.frame

write_csv(data_frame(p_conv=out.frame$pr,p_error=error.estimates$p.error),path=out.file)


