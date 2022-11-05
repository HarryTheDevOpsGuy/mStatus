#!/usr/bin/env bash
GIT_COMMIT="true"
keepLogLines=200
email_tmpl="/tmp/email.html"

env

YELLOW='\033[0;33m'
NC='\033[0m' # No Color

USER_AGENTS=(
'Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36 Edge/44.18363.8131'
'Mozilla/5.0 (Macintosh; Intel Mac OS X 12_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36 Edg/105.0.1343.42'
'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36'
'Mozilla/5.0 (Windows Mobile 10; Android 10.0; Microsoft; Lumia 950XL) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Mobile Safari/537.36 Edge/40.15254.603'
'Mozilla/5.0 (Linux; Android 12; SM-S906N Build/QP1A.190711.020; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/80.0.3987.119 Mobile Safari/537.36'
'Mozilla/5.0 (Linux; Android 12; Pixel 6 Build/SD1A.210817.023; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/94.0.4606.71 Mobile Safari/537.36'
'Mozilla/5.0 (Linux; Android 6.0.1; Nexus 6P Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.83 Mobile Safari/537.36'
'Mozilla/5.0 (Linux; Android 10; HTC Desire 21 pro 5G) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.127 Mobile Safari/537.36'
'Mozilla/5.0 (iPod touch; CPU iPhone 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1'
'Mozilla/5.0 (X11; CrOS x86_64 14989.107.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.5195.134 Safari/537.36'
'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.5195.136 Mobile Safari/537.36'
)

declare -A CERT_INFO=()

log_debug() {
  if [[ ${VERBOSE:-false} == true ]]; then
    local msg=$1
    echo -e "${YELLOW} ${msg} ${NC} ${2}"
  fi
}

####  Slack Notification  ####

datediff() {
  #datediff "$(date -d 'now + 70 minutes' +'%F %T')" "$(date -d 'now' +'%F %T')" "minutes"
    d1=$(date -d "$1" +%s)
    d2=$(date -d "$2" +%s)
    case $3 in
      months ) echo $(( (d1 - d2) / 2629746 )) ;;
      weeks ) echo $(( (d1 - d2) / 604800 )) ;;
      days ) echo $(( (d1 - d2) / 86400 )) ;;
      hours ) echo $(( (d1 - d2) / 3600 )) ;;
      minutes ) echo $(( (d1 - d2) / 60 )) ;;
    esac
}


site_status_html(){
  echo "<table class='datatable' >
      <caption><strong style='color: ${color:-black};'>Website Status</strong></caption>
      <tr><th>URL</th><td>${url}</td><th>Status Code</th><td>${response}</td> </tr>
      <tr> <th>Response Time</th><td>${respontime} Seconds</td><th>Severity</th><td>${severity:-Critical}</td></tr>
      <tr><th>TimeStamp</th> <td>${dateTime}</td><th>Total Downtime</th> <td>${minDiff} Minutes</td></tr>
    </table>"
}


get_ssl_td(){
  lno=1
  for host in ${!CERT_INFO[@]}; do
    cat <<-END
     <tr class="text-$(echo ${CERT_INFO[$host]}|awk -F'|' '{print $4}')"><th scope="row">$lno</th><td>${host}</td><td>$(echo ${CERT_INFO[$host]}|awk -F'|' '{print $1}') days</td><td>$(echo ${CERT_INFO[$host]}|awk -F'|' '{print $2}')</td><td>$(echo ${CERT_INFO[$host]}|awk -F'|' '{print $3}')</td></tr>
END
    lno=$((lno + 1))
  done
}

cert_status_html(){
  export DATATABLE_TITLE="SSL Certificate Status"
  export DATATABLE=$(cat <<-END
      <div class="header-button">
        <a href="https://forms.gle/eH7eFVHboxCR76b77" target="_blank" class="btn btn-common"><i class="fa fa-plus"></i> Submit Host</i></a>
        <a href="https://t.me/mCloudUptime" target="_blank" class="btn btn-common"><i class="fa-brands fa-telegram"></i> Check Alerts</a>
        <a href="https://harrythedevopsguy.medium.com/monitor-website-uptime-status-free-of-cost-311d87d0b991" target="_blank" class="btn btn-border video-popup">Learn More</i></a>
      </div>
     <table id="templatedt" class="table table-hover text-body">
      <thead class="thead-dark"><tr><th scope="col">#</th><th scope="col">Host</th><th scope="col">Expired in</th><th scope="col">Expired on</th><th scope="col">Issuer</th></tr></thead>
      <tbody>
$(get_ssl_td)
      </tbody>
      <tfoot class="thead-dark"><tr><th scope="col">#</th><th scope="col">Host</th><th scope="col">Expired in</th><th scope="col">Expired on</th><th scope="col">Issuer</th></tr></tfoot>
    </table>
END
)
}

### certExpiry
get_reminder_days(){
  NUM=${1:-50}
  declare -ga REMINDER_DAYS=( ${NUM} )
  while [[ ${NUM} -gt '2' ]]; do
    CN=$(( 40 % 2 ))
    if [[ ${CN} == 0 ]]; then
      NUM=$(( NUM / 2 ))
    else
      EVEN=$(( NUM + 1 ))
      NUM=$(( EVEN / 2 ))
    fi
    REMINDER_DAYS+=( ${NUM} )
  done
  # echo "REMINDER_DAYS: ${REMINDER_DAYS[@]}"
}
certExpiry(){
  keyname="${1}"
  scheme="${2%%:*}"
  ssl_fqdn=$(echo "${2}" | awk -F[/:] '{print $4}')
  SSLDATA="/tmp/ssldata.log"
  get_reminder_days "${CERT_REMINDER}"
  touch ${log_dir}/sslcert.log /tmp/ssl.log
  check_ssl=$(grep -c "$(date +'%F'):${keyname}" /tmp/ssl.log)
  if [[ ${check_ssl} -lt 1 ]]; then
      if [[ ${scheme} == 'https' ]]; then
        curl --connect-timeout ${PROBES_TIMEOUT:-$timeout} -A "${USER_AGENTS[$((RANDOM % 10))]}" --cert-status -v https://${ssl_fqdn} 2>&1 | awk 'BEGIN { cert=0 } /^\* Server certificate:/ { cert=1 } /^\*/ { if (cert) print }' > ${SSLDATA}
        EXP_DATE=$(grep "expire date:" ${SSLDATA}|awk -F': ' '{print $2}')
        CERT_ISSUER=$(grep "issuer:" ${SSLDATA}|awk -F': ' '{print $2}'|sed -e 's/=/=\`/g; s/;/\`;/g; s/$/\`/g;')
        ISSUER_NAME=$(grep "issuer:" ${SSLDATA}|tr ';' '\n'|awk -F'=' '/O=/ {print $2}')

        CERT_CNAME=$(grep "subject:" ${SSLDATA}|awk -F': ' '{print $2}'|sed -e 's/=/=\`/g; s/;/\`;/g; s/$/\`/g;')
        CERT_ALTCNAME=$(grep "subjectAltName:" ${SSLDATA}|awk -F': ' '{print $2}'|sed -e 's/"/\`/g;')

        ##### Slack Notification for SSL Cert ######
        max_num=$(IFS=$'\n';echo "${REMINDER_DAYS[*]}" | sort -nr | head -n1)
        today="$(date -d 'now' +'%F %T')"
        remain_days=$(datediff "${EXP_DATE}" "${today}" "days")

        echo "$(date +'%F'):${keyname}" >> "/tmp/ssl.log"
        if [[ ${remain_days} -ge 60 ]]; then
          infotype='success'
        elif [[ ${remain_days} -ge 30 ]]; then
          infotype='info'
        elif [[ ${remain_days} -ge 15 ]]; then
          infotype='warning'
        elif [[ ${remain_days} -ge 0 ]]; then
          infotype='danger'
        fi
        if [[ ! -z ${EXP_DATE} ]]; then
          CERT_INFO[${ssl_fqdn}]="${remain_days}|${EXP_DATE}|${ISSUER_NAME}|${infotype}"
        fi


        for day in ${REMINDER_DAYS[@]}; do
          if [[ ${remain_days} -le ${day} && ! -z ${EXP_DATE} ]];then
            check_alert=$(grep -c "${keyname}:${day}" ${log_dir}/sslcert.log)
            if [[ ${check_alert} -lt 1 ]]; then

              if [[ ${remain_days} -lt 21 ]]; then
                severity="Critical"
              else
                severity="Warning"
              fi

              export SLACK_TITLE=":red_circle: ${severity} | SSL Cert is expiring in ${remain_days} days for https://${ssl_fqdn}."
              export SLACK_MSG="*Domain* : \`${keyname} -> https://${ssl_fqdn}\` \n *Severity * : \`${severity}\` \n *Expiring in * : \`${remain_days} days\` \n *Expired on* : \`${EXP_DATE}\` \n *Cert Issuer* : ${CERT_ISSUER} \n *CNAME* : ${CERT_CNAME}  \n *AltName* : ${CERT_ALTCNAME}  \n *ManagedBy* : *mCloud*"

              # TELEGRAM Notification vars
              TELEGRAM_MSG="
🛑 *${severity} | SSL Cert is expiring in ${remain_days} days for* [${keyname}](https://${ssl_fqdn})
👉 *Description :* SSL Cert is expiring in \`${remain_days}\` days for [${keyname}](https://${ssl_fqdn})
  ▪️ *Domain* : [${keyname}](https://${ssl_fqdn})
  ▪️ *Severity* : \`${severity}\`
  ▪️ *Expiring in * : \`${remain_days} days\`
  ▪️ *Expired on* : \`${EXP_DATE}\`
  ▪️ *Cert Issuer* : ${CERT_ISSUER}
  ▪️ *CNAME* : ${CERT_CNAME}
  ▪️ *AltName* : ${CERT_ALTCNAME}

---
*Managed By* : @HarryTheDevOpsGuy
"
      export email_subject="🛑 ${severity} | SSL Cert is expiring in ${remain_days} days for ${ssl_fqdn}"
echo "<table class='datatable' >
    <caption><strong style='color: ${color:-black};'>SSL Certifcate Details</strong></caption>
    <tr><th>Domain</th><td>https://${ssl_fqdn}</td><th>Expired on</th><td>${EXP_DATE}</td> </tr>
    <tr> <th>Severity</th><td>${severity}</td><th>CNAME</th><td>$(grep "subject:" ${SSLDATA}|awk -F': ' '{print $2}')</td></tr>
    <tr><th>Expiring in</th> <td>${remain_days} days</td><th>ALT Name</th> <td>$(grep "subjectAltName:" ${SSLDATA}|awk -F': ' '{print $2}')</td></tr>
    <tr><th>ManagedBy</th> <td>mCloud</td><th>Cert Issuer</th> <td>$(grep "issuer:" ${SSLDATA}|awk -F': ' '{print $2}')</td></tr>
  </table>" > ${email_tmpl}

              checksendalert=$(grep -c "$(date +'%Y-%m-%d').*${keyname}" ${log_dir}/sslcert.log)
              if [[ "${checksendalert}" -lt "1" ]]; then
                sent_alerts "$(echo ${NOTIFY[@]})"
                echo "${today}->${keyname}->${remain_days} days -  Sent alert for SSL Expiration."
              else
                echo "${today}->${keyname}->${remain_days} days - Skipping SSL Notification. already sent for today."
              fi
              echo ${today}, ${keyname}:${day} >> "${log_dir}/sslcert.log"
              # By default we keep 200 last log entries.  Feel free to modify this to meet your needs.
              echo "$(tail -${keepLogLines} ${log_dir}/sslcert.log)" > "${log_dir}/sslcert.log"

            else
              echo "${today}->${keyname}->${remain_days} days - SSL Notification already Sent for ${day}th day."
            fi

          fi
        done

        echo "${today}->${keyname}->${ssl_fqdn}->${EXP_DATE} [${remain_days} days left]"

      fi
  # else
  #  echo "SSL Already checked for the $(date +'%F') for ${keyname}. will check tomorrow."

  fi
}


####  Slack Notification  ####

sent_alerts(){
  # sent_alerts "id id2"
  echo "Notification sending->${1}"
  for nid in $1; do
    NOTIFY_TYPE="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $1}')"

    case ${NOTIFY_TYPE} in
      slack )
        export SLACK_CLI_TOKEN="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $2}')"
        SLACK_CHANNEL="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $3}')"
        SLACK_MENTIONS=( $(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $4}') )

        mslack chat send --title "${SLACK_TITLE}" --text "${SLACK_MSG} \n *CC:* ${SLACK_MENTIONS[@]}" --channel "${SLACK_CHANNEL}" --filter '.ts' --color ${COLOR:-warning}
        echo "$(date -d 'now' +'%F %T') - Notification sent->${NOTIFY_TYPE}->${SLACK_TITLE}"
        ;;
      telegram )
        telegram_token="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $2}')"
        telegram_gid="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $3}')"
        telegram_mentions=( $(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $4}') )
        TELEGRAM_MSG="${TELEGRAM_MSG}
*CC:* ${telegram_mentions[@]}"

        curl -s -o /dev/null \
         --data parse_mode=MARKDOWN \
         --data chat_id=${telegram_gid} \
         --data text="${TELEGRAM_MSG}" \
         --request POST https://api.telegram.org/bot${telegram_token}/sendMessage
         if [[ ${?} == 0 ]]; then
           echo "$(date -d 'now' +'%F %T') - Notification sent->telegram->${telegram_gid}->${SLACK_TITLE}"
         else
           echo "$(date -d 'now' +'%F %T') - Notification sent->telegram->${telegram_gid}->${SLACK_TITLE}"
         fi
        ;;
      sendgrid )
        export SENDGRID_API_KEY="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $2}')"
        export SENDGRID_SENDER="$(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $3}')"
        declare -a SENDGRID_EMAIL_TO=( $(echo ${NOTIFICATIONS[$nid]}| awk -F '|' '{print $4}') ${EMAILTO[@]} )
        msend_bin=$(which msend)
        if [[ -z ${msend_bin} ]]; then
          sudo curl -sL "https://github.com/HarryTheDevOpsGuy/msend/raw/master/$(uname -p)/msend" -o /usr/bin/msend
          sudo chmod +x /usr/bin/msend
        fi
        mkdir -p ~/.mSend/
        cat > ~/.mSend/msend.conf <<EOL
REPLY_EMAIL_ADDRESS='Harry <HarryTheDevOpsGuy@gmail.com>'
EMAIL_MODE='SENDGRID'
SENDGRID_API_KEY='${SENDGRID_API_KEY}'
EMAIL_FROM='mCloud Automation <${SENDGRID_SENDER:-mcloudautomation@gmail.com}>'
EOL
        echo "Sending email to ${SENDGRID_EMAIL_TO[@]} using sendgrid "
        msend -t "$(echo ${SENDGRID_EMAIL_TO[@]})" -s "${email_subject}" -f "${email_tmpl}"
        echo "$(date -d 'now' +'%F %T') - Sendgrid Notification sent->${SENDGRID_SENDER}->${SENDGRID_EMAIL_TO[@]}->${email_subject}"
        ;;
      * )
        echo "Notification type ${NOTIFY_TYPE} does not supported."
        ;;

    esac




  done

}

git_update(){

  check_date="$(cat ${log_dir}/mstatus.log| awk -F '|' '/RepoCleanUP/ {print $2}'|tail -1)"
  todaydate="$(date +'%Y-%m-%d')"
  if [[ "${todaydate}" == "${check_date}" ]]; then
    cd ${log_dir}
    yesterday=$(date -d 'now -1 days' +'%Y-%m-%d')
    cleanup_date=$(date -d 'now +30 days' +'%Y-%m-%d')
    git ls-files -z | xargs -0 -n1 -I {} -- git log -1 --format="%ai {}" {} |grep -v "${todaydate}\|${yesterday}"|awk '/report.log/ {print $4}'|xargs rm -f
    git remote prune origin && git repack && git prune-packed && git reflog expire --expire=1.month.ago && git gc --aggressive
    echo "RepoCleanUP|${cleanup_date}|true" >> ${log_dir}/mstatus.log
    echo "$(tail -50  ${log_dir}/mstatus.log)" > "${log_dir}/mstatus.log"
  fi

  if [[ "${GIT_COMMIT}" == "true" ]]; then
    cd ${SUBDIR}
    for filekey in $(awk -F'=' '{print $1}' urls.cfg); do
      if [[ ! -f "logs/${filekey}_report.log" ]]; then
        sed -i "/${filekey}=/d" urls.cfg
      fi
    done

    git pull
    git status
    git config --global user.name 'mCloud-Platform'
    git config --global user.email 'mCloudAutomation@gmail.com'
    git add -A --force logs/. urls.cfg ../mcert.html
    git commit -am "[Automated] ${GITHUB_JOB} - Update Health Check Logs"
    git push
  fi
}


# Help command output
usage(){
echo "
script usage: $(basename $0) -s [-c '/opt/configs'] [-h] [-r /tmp/repodir]
    -c    config dir path.
    -r    repo directory path
    -s    publish status page publically
    -q    run script silently.
    -v    Display version
    -V    Verbose mode
    -h    display help page.


example ::
    $(basename $0) -s -c /opt/configs -r /tmp/repodir
"
exit 0
}

while getopts 'c:hvsqVr:' OPTION; do
  case "$OPTION" in
    c) CONFIG_DIR="$OPTARG" ;;
    h) usage ;;
    r) REPO_DIR="$OPTARG" ;;
    s) publish_status=true ;;
    q) git_quite=true ;;
    V) VERBOSE=true ;;
    v)
      echo "Version : ${RELEASE_VER:-1.0}"
      echo "Release Date : ${RELEASE_DT:-31-Aug-22}"
      exit 0
      ;;
    ?) usage ;;
  esac
done
shift "$(($OPTIND -1))"

if [[ -z ${CONFIG_DIR} || -z ${REPO_DIR} ]]; then
  echo "please check config dir and repo dir"
  echo "$(basename $0) -c /opt/configs -r /tmp/repodir"
  exit 0
fi


for (( i = 0; i < ${RUN_MAX:-1}; i++ )); do
    for config_file in ${CONFIG_DIR}/*_config.sh; do
        source ${config_file}
        SUBDIR=${REPO_DIR}/${uid}
        log_dir="${SUBDIR}/logs"
        mkdir -p ${log_dir}

        for cid in ${!CERTS[@]}; do
            NOTIFY=( $(echo ${CERTS[$cid]} | awk -F '|' '{print $1}') )
            CERT_REMINDER="$(echo ${CERTS[$cid]} | awk -F '|' '{print $2}')"
            CERT_HOST=( $(echo ${CERTS[$cid]} | awk -F '|' '{print $3}') )
            EMAILTO=( $(echo ${CERTS[$cid]} | awk -F '|' '{print $4}') )
            # echo "CHECK:::CERT_HOSTS: ${CERT_HOST[@]}"
            for (( d = 0; d < ${#CERT_HOST[@]}; d++ )); do
              dns=$(echo ${CERT_HOST[$d]} | awk -F[/:] '{print $4}' )
              if [[ -z ${dns} ]]; then
                dns="${CERT_HOST[$d]}"
              fi

              f=${dns%.*}; g=${f/./-};k=${g/www-/}
              u="${CERT_HOST[$d]}"
              certExpiry "${k}" "${u}"
            done
        done

        for id in ${!PROBES[@]}; do

            PROBES_PUBLISH="$(echo ${PROBES[$id]} | awk -F '|' '{print $1}')"
            PROBES_TIMEOUT="$(echo ${PROBES[$id]} | awk -F '|' '{print $2}')"
            NOTIFY=( $(echo ${PROBES[$id]} | awk -F '|' '{print $3}') )
            REPEAT_ALERT="$(echo ${PROBES[$id]} | awk -F '|' '{print $4}')"
            PROBES_URLS=( $(echo ${PROBES[$id]} | awk -F '|' '{print $5}') )
            EMAILTO=( $(echo ${PROBES[$id]} | awk -F '|' '{print $6}') )
            publish_status_page=${publish_status:-$PROBES_PUBLISH}


           for (( j = 0; j < ${#PROBES_URLS[@]}; j++ )); do
               fqdn=$(echo ${PROBES_URLS[$j]} | awk -F[/:] '{print $4}' )
               keyprefix=${PROBES_URLS[$j]##*/}
               f=${fqdn%.*}; keyraw=${f/./-};
               if [[ "${fqdn}" != "${keyprefix}" &&  ! -z ${keyprefix} ]]; then
                 key=${keyraw/www-/}-${keyprefix%%.*}
               else
                 key=${keyraw/www-/}
               fi

               url="${PROBES_URLS[$j]}"
               dateTime=$(date +'%F %T')
               touch ${log_dir}/{${key}_report.log,mstatus.log}
               olddate=$(tail -1 ${log_dir}/${key}_report.log |cut -d ',' -f1|sed 's/^\s*//')
               lastResult=$(tail -1 ${log_dir}/${key}_report.log |cut -d ',' -f2|sed 's/^\s*//')

               if [[ "${lastResult}" == "failed" ]]; then
                 PROBES_TIMEOUT=4
                 max_retry=( 1 2 )
               else
                 max_retry=( 1 2 3 4 )
               fi


               if [[ "${publish_status_page,,}" == "true" ]]; then
                 check_url=$(grep -wc "${url}" ${SUBDIR}/urls.cfg)
                 if [[ ${check_url} -lt 1 ]]; then
                   echo "${key}=${url}" >> ${SUBDIR}/urls.cfg
                   echo "CHECK:::UPDATEDURL-$id:${j}:${key}=${url}"
                 fi
               fi


               for n in ${max_retry[@]}; do
                 unset response result reason

                  writeout="[dnslookup]='%{time_namelookup}' [connect]='%{time_connect}' [appconnect]='%{time_appconnect}' [pretransfer]='%{time_pretransfer}' [starttransfer]='%{time_starttransfer}' [time_total]='%{time_total}' [size]='%{size_download}' [response_code]='%{response_code}' [size_request]='%{size_request}' [remote_ip]='%{remote_ip}'"
                  curldata=$(curl -m ${PROBES_TIMEOUT:-5} -A "${USER_AGENTS[$((RANDOM % 10))]}" --connect-timeout ${PROBES_TIMEOUT:-5} -sw "${writeout}" -o /dev/null $url)
                  retcode="$?"
                  request_output="$(echo $curldata|sed "s/\[//g; s/\]=/: /g; s/'//g")"
                  extra_request_data="$(echo $curldata | tr ' ' '\n'|sed "s/\[/  ▪️ */g; s/\]=/* : /g; s/'/\`/g")"
                  eval declare -A RESP_DATA=( ${curldata} )

                  response=${RESP_DATA[response_code]}
                  respontime=$(printf "%.3f" ${RESP_DATA[time_total]})
                 log_debug "$(date +'%T') - ${j}/${n}-> $url ->${PROBES_TIMEOUT:-5}->${respontime}->${response}"

                 if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ] ; then
                   result="success"
                   reason="Up and running[$n]"
                 elif [ "$response" -eq 000 ]; then
                   echo "$(date +'%T') - ${j}/${n}-> $url ->${PROBES_TIMEOUT:-5}->${respontime}->[${response}|${retcode}]"
                   result="failed"
                   case ${retcode} in
                     28 )
                      if [[ ((${RESP_DATA[appconnect]} > 0.000000)) && ((${respontime} > ${PROBES_TIMEOUT:-5})) ]]; then
                        result="success"
                        reason="Up and running[28]"
                      else
                        reason="Operation timed out Error[28]"
                      fi
                      ;;
                     6 ) reason="Could not resolve host[6]" ;;
                     60 ) reason="SSL certificate problem: certificate has expired[60]" ;;
                     * ) reason="Connection Failed [${retcode}]" ;;
                   esac

                 elif [ "$response" -eq 500 ]; then
                   reason="Internal Server Error[$n]"
                   result="failed"
                 elif [ "$response" -eq 502 ]; then
                   reason="Bad Gateway[$n]"
                   result="failed"
                 elif [ "$response" -eq 503 ]; then
                   reason="the service is unavailable[$n]"
                   result="failed"
                 elif [ "$response" -gt 400 ] && [ "$response" -lt 500 ] ; then
                   reason="Client Error"
                   result="failed"
                 else
                   reason="Unable to access[$n]"
                   result="failed"
                 fi
                 if [ "$result" = "success" ]; then
                   break
                 fi
                 sleep 2
               done



               ################# Slack Notification Rules.##############
               minDiff=$(datediff "${dateTime}" "${olddate}" "minutes")
               # log_debug "${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult}->${result}->${response}->${respontime}Sec->[${minDiff} min > ${REPEAT_ALERT} min]"

               if [[ "${minDiff}" -ge "${REPEAT_ALERT}" || ${lastResult} != ${result} ]]; then

                   if [[ ! -z ${result} && ! -z ${lastResult} ]]; then

                       if [[ ("${result}" == "failed" && "${lastResult}" == "${result}") && (${minDiff} -ge ${REPEAT_ALERT}) ]]; then

                          #### SLACK NOTIFICATION CONFIG ####
                           SLACK_TITLE=":red_circle: Critical | still getting ${response} - ${reason} on ${url} for ${minDiff} minutes"
                           SLACK_MSG="*URL* : \`${key}->${url}\` \n *Status* : \`${response} - ${reason}\` \n *Response Time* : \`${respontime} Seconds\` \n *Alert Severity* : \`Critical\` \n *Status Code* : \`${response}\` \n *ManagedBy* :  \`mCloud\`"
                           COLOR='danger'

                           # TELEGRAM Notification vars
                           TELEGRAM_MSG="
🛑 *Critical | Still getting ${response} - ${reason} on* [${key}](${url}) *for ${minDiff} minutes*
👉 *Description :* still getting \`${response} - ${reason}\` on [${key}](${url}) for \`${minDiff} minutes\`

  ▪️ *URL* : [${key}](${url})
  ▪️ *Status* : \`${response} - ${reason}\`
  ▪️ *Response Time* : \`${respontime} Seconds\`
  ▪️ *Alert Severity* : \`Critical\`
  ▪️ *Status Code* : [${response}](https://www.restapitutorial.com/httpstatuscodes.html)
  ▪️ *Down at* : \`${dateTime}\`.

*Extra info*
${extra_request_data}

---
*Managed By* : @HarryTheDevOpsGuy"
                           # Email Sendgrid email send by mSend.
                           email_subject="🛑 Critical | still getting ${response} - ${reason} on ${url} for ${minDiff} minutes"
                           site_status_html > ${email_tmpl}

                           sent_alerts "$(echo ${NOTIFY[@]})"
                           echo "${dateTime} - ${id}->${j}->${key}->${lastResult}->${result}->${response}->${respontime}Sec->[${minDiff} min > ${REPEAT_ALERT} min]->RepeatAlert"

                       elif [[ "${result}" == 'failed' && ${lastResult} != ${result} ]]; then

                          # Slack Notification vars
                           SLACK_TITLE=":red_circle: Critical | Getting ${response} - ${reason} on ${url}"
                           SLACK_MSG="*URL* : \`${key}->${url}\` \n *Status* : \`Getting ${response} - ${reason}\` \n *Response Time* : \`${respontime} Seconds\` \n *Alert Severity* : \`Critical\` \n *Status Code* : \`${response}\`  \n *Down at* : \`${dateTime}\`."
                           COLOR='danger'

                           # TELEGRAM Notification vars
                           TELEGRAM_MSG="
🛑 *Critical | Getting ${response} - ${reason} on* [${key}](${url})
👉 *Description :* Getting \`${response} - ${reason}\` on [${key}](${url})

  ▪️ *URL* : [${key}](${url})
  ▪️ *Status* : \`${response} - ${reason}\`
  ▪️ *Response Time* : \`${respontime} Seconds\`
  ▪️ *Alert Severity* : \`Critical\`
  ▪️ *Status Code* : [${response}](https://www.restapitutorial.com/httpstatuscodes.html)
  ▪️ *Down at* : \`${dateTime}\`.

*Extra info*
${extra_request_data}

---
*Managed By* : @HarryTheDevOpsGuy"
                          # Email Sendgrid email send by mSend.
                          email_subject="🛑 Critical | Getting ${response} - ${reason} on ${url} | ${respontime} Seconds"
                          site_status_html > ${email_tmpl}

                          sent_alerts "$(echo ${NOTIFY[@]})"
                          echo "${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult}->${result}->${response}->${respontime}Sec->AlertTriggered"

                       elif [[ "${result}" == "success" && ${lastResult} != ${result} ]]; then

                           SLACK_TITLE=":large_green_circle: Resolved | ${url} is working now - ${response} | ${respontime} Seconds"
                           SLACK_MSG="*URL* : \`${key}->${url}\` \n *Status* : \`${url} is up and running\` \n *Response Time* : \`${respontime} Seconds\` \n *Alert Severity* : \`Critical\` \n *Status Code* : \`${response}\`  \n *Down at* : \`${dateTime}\`. \n *Total Downtime* :  \`${minDiff}\` minutes."
                           COLOR='good'

                           # TELEGRAM Notification vars
                           TELEGRAM_MSG="
🟢 *Resolved |* [${key}](${url}) *is now up and running - ${response}*
👉 *Description :* [${key}](${url}) is now accessible - ${response}.

  ▪️ *URL* : [${key}](${url})
  ▪️ *Status* : [${key}](${url}) is up and running
  ▪️ *Response Time* : \`${respontime} Seconds\`
  ▪️ *Alert Severity* : \`Critical\`
  ▪️ *Status Code* : [${response}](https://www.restapitutorial.com/httpstatuscodes.html)
  ▪️ *Total Downtime* : \`${minDiff}\` minutes.

*Extra info*
${extra_request_data}
---
*Managed By* : @HarryTheDevOpsGuy"

                          # Email Sendgrid email send by mSend.
                          email_subject="🟢 Resolved | ${url} is working now - ${response} | ${respontime} Seconds"
                          site_status_html > ${email_tmpl}
                          sent_alerts "$(echo ${NOTIFY[@]})"
                          echo "${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult}->${result}->${response}->${respontime}sec->ResolvedAlert"

                       elif [[ ${result} == 'success' && ${lastResult} == ${result} ]]; then
                           echo "OK : ${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult}->${result}->${response}->${respontime} Seconds - [${minDiff}:${REPEAT_ALERT}]"
                       else
                           echo "SomeThingIsNotHandled : ${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult}->${result}->${response} - [${minDiff}:${REPEAT_ALERT}]"
                       fi

                     else
                     echo "VariableEmpty: ${dateTime} - ${id}->${j}->${key}->${lastResult:-lastResultEmpty}->${result:-resultEmpty}->${response}->${respontime} Seconds - [${minDiff}:${REPEAT_ALERT}]"
                     echo $dateTime, $result >> "${log_dir}/${key}_report.log"
                   fi
                     echo $dateTime, $result >> "${log_dir}/${key}_report.log"
                     # By default we keep 200 last log entries.  Feel free to modify this to meet your needs.
                     echo "$(tail -${keepLogLines} ${log_dir}/${key}_report.log)" > "${log_dir}/${key}_report.log"
                     log_debug "${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult:-lastResultEmpty}->${result:-resultEmpty}->${response}->${respontime} Seconds - [${minDiff}:${REPEAT_ALERT}]"

               elif [[ ${lastResult} == ${result} && ${result} == 'failed' ]];then
                 echo "Next alert in $(( REPEAT_ALERT - minDiff )) minutes: ${dateTime} - ${id}->${j}/${#PROBES_URLS[@]}->${key}->${lastResult}->${result}->${response}->${respontime} Seconds - [${minDiff}:${REPEAT_ALERT}]"
               fi
               # check certExpiry
               certExpiry "${key}" "${url}"
           done
           # echo "CHECK:::TEST2 ${dateTime} - ${key}->${lastResult:-lastResultEmpty}->${result:-resultEmpty}->${response}->${respontime} Seconds"
        done

        # commit data for every config file.
        if [[ "${git_quite:-false}" == "true" ]]; then
          git_update > /dev/null 2>&1
        else
          git_update
        fi

        # sleep ${PROBES_INTERVAL}
    done
    if [[ ${#CERT_INFO[@]} -gt 1 ]]; then
      echo "${dateTime}: Update SSL Cert Status Page for ${#CERT_INFO[@]}"
      cert_status_html
      envsubst < ${REPO_DIR}/template.html > ${REPO_DIR}/mcert.html
      git_update > /dev/null 2>&1
    fi


done
