#!/usr/bin/env bash 
#
# NAME
#     logparser - Log parser for AWS ELB logs from S3 from an AWSCLI enabled host
#
# SYNOPSIS
#   
#   a tool that will fetch the load balancer logs from the S3 bucket “techtest-alb-logs” and provide the following reporting
#   options :
#   - top N error codes for a given period of time :
#   # logparser getcodes --from 2018/07/01 --to 2018/07/07 --max N
#   - top N urls for an error passed as parameter for a given period of time:
#   # logparser geturls --code 404 --from 2018/07/01 --to 2018/07/07 --max N
#   - top N user agents for a given http code for a given period of time:
#   # logparser getUAs --code 404 --from 2018/07/01 --to 2018/07/07 --max N
#   - a synthetic report for a given period of time:
#   # logparser getreport --from 2018/07/01 --to 2018/07/07 --max N
#   The synthetic report is intended to be human readable or a csv document providing a breakdown of the logged traffic for
#   review and analysis. It is up to you to pick the content that you deem useful.
#   The tool:
#   should be able to use absolute (2018/07/01) date stamps and relative date and time stamps. The first
#   example above should be callable as:
#   # logparser geturls --code 404 --from 2018/07/01 --to 2018/07/07
#   # logparser geturls --code 404 --for 7 days
#   # logparser geturls --code 404 --for 5 hours
#   Relative timestamps should be relative to the date and time of the query
#   should interpret the lack of a “--max” parameter as in “provide all results for that metric”
#
# AUTHOR
#      Rafael Sanchez, 2018
#      
# CONTRIBUTORS
#
#
#

if [ -z "$1" ]; then
        cat <<EOF
USAGE
        $(basename $BASH_SOURCE) [options]

OPTIONS
         getcodes 
                return HTTP status codes

         geturls
                return URL based output 

         getuas
                return User Agent activity

        --code 
                specify HTTP return code

                1xx 
                2xx     
                3xx     
                4xx     
                5xx     

        
        --from 
                Provide from date: e.g
                YYYY/MM/DD

        --to 
                Provide to date: e.g
                YYYY/MM/DD

        --max 
                specify max count

        --for
                specify relactive date or time



EXAMPLES
 $(basename $BASH_SOURCE)  getcodes --from 2018/07/01 --to 2018/07/07 --max N
 $(basename $BASH_SOURCE)  geturls --code 404 --from 2018/07/01 --to 2018/07/07 --max N
 $(basename $BASH_SOURCE) getUAs --code 404 --from 2018/07/01 --to 2018/07/07 --max N
 $(basename $BASH_SOURCE) getreport --from 2018/07/01 --to 2018/07/07 --max N  # Get report on when ELB did not return the same status code that the backend server that handled it #
 $(basename $BASH_SOURCE) geturls --code 404 --from 2018/07/01 --to 2018/07/07
 $(basename $BASH_SOURCE) geturls --code 404 --for 7 days
 $(basename $BASH_SOURCE) geturls --code 404 --for 5 hours


EOF
        exit 1
fi

set_params()

{
optspec=":hv-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                from)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    FROM=${val};
                    ;;
                to)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    TO=${val};
                    ;;
                max)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    MAX=${val};
                    ;;
                for)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    FOR=${val};
                    ;;
                code)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    CODE=${val};
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        /bin/echo "Unknown option --${OPTARG}" >&2
                    fi
                    ;;
            esac;;
        h)
            /bin/echo "" >&2
            exit 2
            ;;
        v)
            /bin/echo "Parsing option: '-${optchar}'" >&2
            ;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                /bin/echo "Non-option argument: '-${OPTARG}'" >&2
            fi
            ;;
    esac
done
}


get_prep_file()

{
        mkdir ./tmp
        while  [ "$CURRENT" \< "$ENDDATE" ]; do
            aws s3 cp s3://techtest-alb-logs/AWSLogs/ACCOUNT_ID@/elasticloadbalancing/REGION@/"$CURRENT"/ ./tmp/ --recursive --region us-east-2@ > /dev/null
            #aws s3 sync --exclude "*" --include "*$(date +%Y-%m-%d)*" "s3://llpp/AWSLogs/" "./tmp" --region us-east-2
            CURRENT=$( date +%Y/%m/%d --date "$CURRENT +1 day" )
        done
        gzip -d ./tmp/*.gz
        tail -q ./tmp/* | sort | python -c "import sys, re; [sys.stdout.write('\t'.join(re.split(r'\s(?=(?:[^\"]|\"[^\"]*\")*$)', line)) + '\n') for line in sys.stdin]" > "$TSVFILE"
        rm -rf ./tmp
}

##################### set variables for functional options  ########################

set_params $2 $3 $4 $5 $6 $7 $8 $9

CURRENT="$FROM"
ENDDATE=$( date +%Y/%m/%d --date "$TO +1 day" )

# FOR --for 7days / 5 hours use :   date +%Y/%m/%d --date "2018/12/20 +1 day"
# date --date="2018/08/21 -2 day" +%Y-%m-%d 	        	date +%Y/%m/%d --date "2018/12/20 +1 day"

TSVFILE=$(date +%Y-%m-%d)_AWSELB_logfile_$(date '+%m%d%y%H%M%S').tsv

##################### Run functional options  ########################

###GETURLS###

if [ "$1" == "geturls" ] && [ -n "$CODE" ] && [ -n "$FROM" ] && [ -n "$TO" ] ; then

get_prep_file

	if [ -n "$MAX" ]; then
		cat "$TSVFILE"  | tr "\\t" "," | cut -d, -f 9,13  | sort | grep ""$CODE"," | uniq -c |sort -nr | head -"$MAX"
	elif [ -z "$MAX" ]; then
		cat "$TSVFILE"  | tr "\\t" "," | cut -d, -f 9,13  | sort | grep ""$CODE","
	fi

###GETCODES###

elif [ "$1" == "getcodes" ] && [ -n "$FROM" ] && [ -n "$TO" ] ; then

get_prep_file

	if [ -n "$MAX" ]; then
		awk '{print $9}' "$TSVFILE" |sort | uniq -c | sort -nr | head -"$MAX"
	elif [ -z "$MAX" ]; then
		awk '{print $9}' "$TSVFILE" |sort | uniq -c 
	fi

###Get User Agent activity###

elif [ "$1" == "getuas" ] && [ -n "$CODE" ] && [ -n "$FROM" ] && [ -n "$TO" ] ; then

get_prep_file

	if [ -n "$MAX" ]; then

		cat "$TSVFILE" | tr "\\t" "," | cut -d, -f 9,14,15 | sort | grep ""$CODE"," | uniq -c |sort -nr | head -"$MAX" #| awk '{print $2" "$3}'
	elif [ -z "$MAX" ]; then
		cat "$TSVFILE"  | tr "\\t" "," | cut -d, -f 9,14  | sort | grep ""$CODE","

	fi

############### For getreport OPT, I am providing instances when the ELB did not return the same status code than the backend server that handled it 

elif [ "$1" == "getreport" ] && [ -n "$CODE" ] && [ -n "$FROM" ] && [ -n "$TO" ] ; then

get_prep_file

	if [ -n "$MAX" ]; then

		#awk '$10 != $9 {print $0}' "$TSVFILE" |sort |grep "$CODE" | uniq -c |sort -nr | head -"$MAX" | tr "\\t" ","
		awk '$10 != $9 {print $0}' "$TSVFILE" | tr "\\t" "," | sort -u -t, -k 9  | grep ","$CODE"," #| uniq -c |sort -nr | head -"$MAX" 
	elif [ -z "$MAX" ]; then
		#awk '$10 != $9 {print $0}' "$TSVFILE" |grep "$CODE" | tr "\\t" ","
		awk '$10 != $9 {print $0}' "$TSVFILE" | tr "\\t" ","| grep ","$CODE"," 
	fi

fi

