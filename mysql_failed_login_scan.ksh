#!/bin/ksh

############################################################
## Script:  mysql_failed_login_scan.ksh
##
## Purpose: The purpose of this script is to scan the MySQL
##          Servers for failed login attempts
##
## Syntax:  mysql_failed_login_scan.ksh < Option 1 >
##
## Dependencies: None
##
## Input:       Option 1  -> [ 'ALL' | BLANK ]                        - Scan all available MySQL Servers
##                           '<Shard>'                                - Scan all available MySQL Servers associated with the given shard
##                           [ '<Server Name>' | '<IP Address>' ]     - Scan the MySQL Server based upon the server's name or IP address
## Output:      None
##
## History:
## Date        Developer     Information
## ----------  ------------  -------------------------------
## 04/01/2014  J. Jokuti     Initial Release
## 02/03/2015  J. Jokuti     Modified code to use riot_sgdb database tables
##
## COPYRIGHT 2014 BY RIOT GAMES. ALL RIGHTS RESERVED.
############################################################
BASENAME=`basename $0`
OPTION1=${1}

SUBJECT="MySQL Server - Failed Login Attempt"
PROCESS_ERROR="WARNING: Another ${BASENAME} ${OPTION1} process is still running. This currently running process is being aborted."
SQL_DOWN_ERROR="ERROR: The DBADMIN1 MySQL Server is not running."
NO_SERVERS_ERROR="ERROR: There were no MySQL Servers selected for the failed login scan."

TMPSQL="/var/tmp/tmp_sql_$$"
TMPOUT="/var/tmp/tmp_out_$$"
TMPSERVERS="/var/tmp/tmp_servers_$$"
TMPLOG="/var/tmp/tmp_log_$$"
TMPMSG="/var/tmp/tmp_msg_$$"
NOREPLY_ADDR="noreply@riotgames.com"
DBA_EMAIL_ADDR="dba@riotgames.com"

############################################################
##
## Function: check_process
##
## Check if another process is still running. 
## If so, terminate this process.
##
############################################################
check_process()
{
    PROC_FLAG=`ps -ef | grep "${BASENAME} ${OPTION1}" | egrep -v "grep" | wc -l`

    if [ ${PROC_FLAG} -gt 3 ];
    then
        echo "${PROCESS_ERROR}" | mail -s "${SUBJECT}" "${DBA_EMAIL_ADDR}" -- -F "MySQL Server" -f ${NOREPLY_ADDR}
        exit 1
    fi

    return 0
}

############################################################
##
## Function: get_mysql_servers
##
## Query the DBADMIN1 MySQL Server for a list of servers
##
############################################################
get_mysql_servers()
{
    SQL_FLAG=`ps -ef | grep mysqld | egrep -v grep | wc -l`
    if [ ${SQL_FLAG} -eq 0 ];
    then
        echo "${SQL_DOWN_ERROR}" | mail -s "${SUBJECT}" "${DBA_EMAIL_ADDR}" -- -F "`echo ${HOSTNAME} | tr '[:lower:]' '[:upper:]'` MySQL Server" -f ${NOREPLY_ADDR}
        exit 2
    fi

    ### Input Argument: ALL or None
    if [ "${1}" = "" ] || [ "${1}" = "ALL" ];
    then
        echo "SELECT CONCAT(s.server_name, '|', " > ${TMPSQL}
        echo "              s.ip_addr, '|', " >> ${TMPSQL}
        echo "              IFNULL(DATE_FORMAT(sr.end_dt, '%y%m%d_%H:%i:00'), ''), '|', " >> ${TMPSQL}
        echo "              IFNULL(sr.log_file, ''), '|', " >> ${TMPSQL}
        echo "              CASE ROUND(TIME_TO_SEC(TIMEDIFF(NOW(), IFNULL(sr.update_dt, DATE_SUB(NOW(), INTERVAL 5 MINUTE))))/60/5)*60 WHEN 0 THEN 60 " >> ${TMPSQL}
        echo "              ELSE ROUND(TIME_TO_SEC(TIMEDIFF(NOW(), IFNULL(sr.update_dt, DATE_SUB(NOW(), INTERVAL 5 MINUTE))))/60/5)*60 END) AS INFO " >> ${TMPSQL}
        echo "  FROM riot_sgdb.riot_servers s " >> ${TMPSQL}
        echo "  JOIN riot_sgdb.riot_server_regions r " >> ${TMPSQL}
        echo "    ON r.ip_addr = s.ip_addr " >> ${TMPSQL}
        echo "   AND r.port_nbr = s.port_nbr " >> ${TMPSQL}
        echo "  JOIN riot_sgdb.riot_shards d " >> ${TMPSQL}
        echo "    ON d.region_id = r.region_id " >> ${TMPSQL}
        echo "  LEFT JOIN riot_sgdb.failed_logins_scan_dt_range sr " >> ${TMPSQL}
        echo "    ON sr.ip_addr = s.ip_addr " >> ${TMPSQL}
        echo " WHERE s.status = 'A' " >> ${TMPSQL}
        echo "   AND s.port_nbr = 3306 " >> ${TMPSQL}
        echo "   AND d.status = 'A' " >> ${TMPSQL}
        echo "   AND NOT EXISTS (SELECT 1 FROM riot_sgdb.failed_logins_exempt_servers e WHERE e.ip_addr = s.ip_addr AND e.status = 'A') " >> ${TMPSQL}
        echo " ORDER BY d.shard_name, s.server_name; " >> ${TMPSQL}
    else 
        ### Input Argument: Shard
        INPUT_LEN=`echo ${1} | wc -L`
        if [ ${INPUT_LEN} -le 5 ];
        then
            echo "SELECT CONCAT(s.server_name, '|', " > ${TMPSQL}
            echo "              s.ip_addr, '|', " >> ${TMPSQL}
            echo "              IFNULL(DATE_FORMAT(sr.end_dt, '%y%m%d_%H:%i:00'), ''), '|', " >> ${TMPSQL}
            echo "              IFNULL(sr.log_file, ''), '|', " >> ${TMPSQL}
            echo "              CASE ROUND(TIME_TO_SEC(TIMEDIFF(NOW(), IFNULL(sr.update_dt, DATE_SUB(NOW(), INTERVAL 5 MINUTE))))/60/5)*60 WHEN 0 THEN 60 " >> ${TMPSQL}
            echo "              ELSE ROUND(TIME_TO_SEC(TIMEDIFF(NOW(), IFNULL(sr.update_dt, DATE_SUB(NOW(), INTERVAL 5 MINUTE))))/60/5)*60 END) AS INFO " >> ${TMPSQL}
            echo "  FROM riot_sgdb.riot_servers s " >> ${TMPSQL}
            echo "  JOIN riot_sgdb.riot_server_regions r " >> ${TMPSQL}
            echo "    ON r.ip_addr = s.ip_addr " >> ${TMPSQL}
            echo "   AND r.port_nbr = s.port_nbr " >> ${TMPSQL}
            echo "  JOIN riot_sgdb.riot_shards d " >> ${TMPSQL}
            echo "    ON d.region_id = r.region_id " >> ${TMPSQL}
            echo "  LEFT JOIN riot_sgdb.failed_logins_scan_dt_range sr " >> ${TMPSQL}
            echo "    ON sr.ip_addr = s.ip_addr " >> ${TMPSQL}
            echo " WHERE d.shard_name = '${1}' " >> ${TMPSQL}
            echo "   AND s.status = 'A' " >> ${TMPSQL}
            echo "   AND s.port_nbr = 3306 " >> ${TMPSQL}
            echo "   AND d.status = 'A' " >> ${TMPSQL}
            echo "   AND NOT EXISTS (SELECT 1 FROM riot_sgdb.failed_logins_exempt_servers e WHERE e.ip_addr = s.ip_addr AND e.status = 'A') " >> ${TMPSQL}
            echo " ORDER BY s.server_name; " >> ${TMPSQL}
        else
            ### Input Argument: Server Name or IP Address
            echo "SELECT CONCAT(s.server_name, '|', " > ${TMPSQL}
            echo "              s.ip_addr, '|', " >> ${TMPSQL}
            echo "              IFNULL(DATE_FORMAT(sr.end_dt, '%y%m%d_%H:%i:00'), ''), '|', " >> ${TMPSQL}
            echo "              IFNULL(sr.log_file, ''), '|', " >> ${TMPSQL}
            echo "              CASE ROUND(TIME_TO_SEC(TIMEDIFF(NOW(), IFNULL(sr.update_dt, DATE_SUB(NOW(), INTERVAL 5 MINUTE))))/60/5)*60 WHEN 0 THEN 60 " >> ${TMPSQL}
            echo "              ELSE ROUND(TIME_TO_SEC(TIMEDIFF(NOW(), IFNULL(sr.update_dt, DATE_SUB(NOW(), INTERVAL 5 MINUTE))))/60/5)*60 END) AS INFO " >> ${TMPSQL}
            echo "  FROM riot_sgdb.riot_servers s " >> ${TMPSQL}
            echo "  LEFT JOIN riot_sgdb.failed_logins_scan_dt_range sr " >> ${TMPSQL}
            echo "    ON sr.ip_addr = s.ip_addr " >> ${TMPSQL}
            echo " WHERE (s.server_name = '${1}' OR s.ip_addr = '${1}') " >> ${TMPSQL}
            echo "   AND s.status = 'A' " >> ${TMPSQL}
            echo "   AND s.port_nbr = 3306 " >> ${TMPSQL}
            echo "   AND NOT EXISTS (SELECT 1 FROM riot_sgdb.failed_logins_exempt_servers e WHERE e.ip_addr = s.ip_addr AND e.status = 'A'); " >> ${TMPSQL}
        fi
    fi

    mysql --user=scanuser --password='************' --connect-timeout=10 --host=dbadmin1 < ${TMPSQL} | tail -n+2 > ${TMPSERVERS}

    if ! [ -s ${TMPSERVERS} ];
    then
        printf "${NO_SERVERS_ERROR}\n\nSQL Statement:\n" > ${TMPMSG}
        cat ${TMPSQL} >> ${TMPMSG}
        cat ${TMPMSG} | mail -s "${SUBJECT}" "${DBA_EMAIL_ADDR}" -- -F "`echo ${HOSTNAME} | tr '[:lower:]' '[:upper:]'` MySQL Server" -f ${NOREPLY_ADDR}
        rm -f ${TMPSQL} ${TMPSERVERS} ${TMPMSG}
        exit 3
    fi

    rm -f ${TMPSQL}

    return 0
}

############################################################
##
## Function: send_notification
##
## Determine if a login failure has occurred and notify the
## DBA Team
##
############################################################
send_notification()
{
    echo "SELECT CONCAT('<div align=\"center\">', s.server_name, '</div>') AS server_name," > ${TMPSQL}
    echo "       CONCAT('<div align=\"center\">', h.ip_addr, '</div>') AS ip_addr," >> ${TMPSQL}
    echo "       CONCAT('<div align=\"center\">', DATE_FORMAT(h.log_dt, '%m/%d/%Y %l:%i:%s %p'), '</div>') AS log_dt," >> ${TMPSQL}
    echo "       CONCAT('<div align=\"center\">', h.user, '</div>') AS user," >> ${TMPSQL}
    echo "       CONCAT('<div align=\"center\">', h.host, '</div>') AS host," >> ${TMPSQL}
    echo "       CONCAT('<div align=\"center\">', h.pwd_used, '</div>') AS pwd_used," >> ${TMPSQL}
    echo "       CONCAT('<div align=\"center\">', h.fail_cnt, '</div>') AS fail_cnt" >> ${TMPSQL}
    echo "  FROM riot_sgdb.failed_logins_history h" >> ${TMPSQL}
    echo "  JOIN riot_sgdb.failed_logins_users u" >> ${TMPSQL}
    echo "    ON h.user LIKE u.user" >> ${TMPSQL}
    echo "   AND h.ip_addr LIKE u.ip_addr " >> ${TMPSQL}
    echo "  JOIN riot_sgdb.riot_servers s" >> ${TMPSQL}
    echo "    ON s.ip_addr = h.ip_addr" >> ${TMPSQL}
    echo " WHERE h.ip_addr = '${2}'" >> ${TMPSQL}
    echo "   AND h.log_dt >= STR_TO_DATE('${3}', '%y%m%d %k:%i:%s')" >> ${TMPSQL}
    echo "   AND h.log_dt < STR_TO_DATE('${4}', '%y%m%d %k:%i:%s')" >> ${TMPSQL}
    echo "   AND u.status = 'A'" >> ${TMPSQL}
    echo "   AND NOT EXISTS (SELECT 1 FROM riot_sgdb.nexpose_servers n WHERE n.ip_addr = h.host)" >> ${TMPSQL}
    echo " ORDER BY s.server_name, h.log_dt;" >> ${TMPSQL}

    mysql --user=scanuser --password='************' --connect-timeout=15 --host=dbadmin1 < ${TMPSQL} > ${TMPOUT}

    OUT_FLAG=`cat ${TMPOUT} | wc -l`

    if [ ${OUT_FLAG} -gt 0 ];
    then
        echo "<html><body>" > ${TMPMSG}
        echo "<H3>Failed login attempts detected on the ${1} (${2}) MySQL Server</H3>" >> ${TMPMSG}

        echo "<table style=\"width: 840px;\" border=0> <col width=\"130\"> <col width=\"100\"> <col width=\"170\"> <col width=\"130\"> <col width=\"100\"> <col width=\"110\"> <col width=\"100\">" >> ${TMPMSG}
        echo "<tr><th>Server</th><th>IP Address</th><th>Log Date</th><th>User Name</th><th>User Host</th><th>Password Used</th><th>Failure Cnt</th></tr>" >> ${TMPMSG}

        cat ${TMPOUT} | sed 's/^/<tr><td>/g' | sed 's/$/<\/td><\/tr>/g' | sed 's/\t/<\/td><td>/g' | tail -n+2 >> ${TMPMSG}
        echo "</table>" >> ${TMPMSG}
        echo "</body></html>" >> ${TMPMSG}

        cat ${TMPMSG} | mail -s "$(echo -e "${1} ${SUBJECT}\nContent-Type: text/html")" "${DBA_EMAIL_ADDR}" -- -F "${1} MySQL Server" -f ${NOREPLY_ADDR}

        rm -f ${TMPSQL} ${TMPOUT} ${TMPMSG}
    fi

    return 0
}

############################################################
##
## Main Body
##
############################################################
CUR_DT=`date "+%Y-%m-%d %k:%M:%S"`
echo "Scan Start: ${CUR_DT}"

check_process

get_mysql_servers "${OPTION1}"

for INFO in `cat ${TMPSERVERS}`
do
    SERVER=`echo ${INFO} | cut -f1 -d"|"`
    IPADDR=`echo ${INFO} | cut -f2 -d"|"`
    START_DT=`echo ${INFO} | cut -f3 -d"|" | sed 's/_0/  /g' | sed 's/_/ /g'`
    LOG_FILE=`echo ${INFO} | cut -f4 -d"|"`
    TAIL_LINES=`echo ${INFO} | cut -f5 -d"|"`
    echo "SERVER: ${SERVER} (${IPADDR})  START_DT: ${START_DT}  LOG_FILE: ${LOG_FILE}  TAIL_LINES: ${TAIL_LINES}"   

    ssh -i /var/lib/nagios/mysql_id_rsa -o NumberOfPasswordPrompts=0 -o StrictHostKeyChecking=no mysql@${IPADDR} "if [ \"${LOG_FILE}\" != \"\" ]; then LOG=\"${LOG_FILE}\"; else ls -l /etc/my.cnf | cut -c8 | grep 'r' > /dev/null; if [ $? -eq 0 ]; then LOG=$(cat /etc/my.cnf | grep log_error| awk '{print $3}'); else sudo -l /bin/cat | grep 'cat' > /dev/null; if [ $? -eq 0 ]; then LOG=$(sudo cat /etc/my.cnf | grep log_error| awk '{print $3}'); fi; fi; fi; if [ \"${START_DT}\" != \"\" ]; then STT=\"${START_DT}\"; else STT=\"\`date --date=\"10 minutes ago\" \"+%y%m%d %k:%M:00\"\`\"; fi; EDT=\"\`date \"+%y%m%d %k:%M:00\"\`\"; tail -${TAIL_LINES} \$LOG | grep 'Access denied' | awk -F, -v SD=\"\$STT\" -v ED=\"\$EDT\" '{if (\$1 >= SD && \$1 < ED) print}' | uniq -c | awk -v SD=\"\$STT\" -v ED=\"\$EDT\" -v LF=\"\$LOG\" '{print} END{print \"ROWS: \" NR \"\nSTART_DT: \" SD \"\nEND_DT: \" ED \"\nLOG_FILE: \" LF}'" > ${TMPLOG}

    ROWS_FLAG=`cat ${TMPLOG} | grep "^ROWS: " | wc -l`
    if [ ${ROWS_FLAG} -gt 0 ];
    then
        cat ${TMPLOG} | grep "^ROWS: "

        ROWS_FLAG=`cat ${TMPLOG} | grep "ROWS: 0" | wc -l`
        if [ ${ROWS_FLAG} -eq 0 ];
        then
            for MSG in `cat ${TMPLOG} | grep "Access denied" | awk '{print $1 "|" $2 "_" $3 "|" $9 "|" $12}' | tr -d ")"`
            do
                FAILCNT=`echo ${MSG} | cut -f1 -d"|"`
                LOG_DT=`echo ${MSG} | cut -f2 -d"|" | tr "_" " "`
                USERINFO=`echo ${MSG} | cut -f3 -d"|" | tr -d "'"`
                USERNAME=`echo ${USERINFO} | cut -f1 -d"@"`
                USERHOST=`echo ${USERINFO} | cut -f2 -d"@"`
                PWDUSED=`echo ${MSG} | cut -f4 -d"|"`

                echo "INSERT IGNORE INTO riot_sgdb.failed_logins_history (ip_addr, log_dt, user, host, pwd_used, fail_cnt) VALUES ('${IPADDR}', STR_TO_DATE('${LOG_DT}', '%y%m%d %k:%i:%s'), '${USERNAME}', '${USERHOST}', '${PWDUSED}', ${FAILCNT});" >> ${TMPSQL}
            done
        fi

        START_DT=`cat ${TMPLOG} | grep "^START_DT: " | cut -c11-`
        END_DT=`cat ${TMPLOG} | grep "^END_DT: " | cut -c9-`
        LOG_FILE=`cat ${TMPLOG} | grep "^LOG_FILE: " | cut -c11-`

        if [ "${START_DT}" = "" ] || [ "${END_DT}" = "" ] || [ "${LOG_FILE}" = "" ];
        then
            echo "ERROR: Invalid variable value detected: START_DT=${START_DT}, END_DT=${END_DT}, LOG_FILE=${LOG_FILE}"
        else
            echo "REPLACE INTO riot_sgdb.failed_logins_scan_dt_range (ip_addr, start_dt, end_dt, log_file, update_dt) VALUES ('${IPADDR}', STR_TO_DATE('${START_DT}', '%y%m%d %k:%i:%s'), STR_TO_DATE('${END_DT}', '%y%m%d %k:%i:%s'), '${LOG_FILE}', NOW());" >> ${TMPSQL}
        fi

        mysql --user=scanuser --password='************' --host=dbadmin1 < ${TMPSQL} > ${TMPOUT}
    
        rm -f ${TMPSQL} ${TMPOUT}
    else
        echo "ERROR: Remote connection failed to the ${SERVER} (${IPADDR}) server"
    fi

    rm -f ${TMPLOG}

    send_notification ${SERVER} ${IPADDR} "${START_DT}" "${END_DT}"
done

rm -f ${TMPSERVERS}

CUR_DT=`date "+%Y-%m-%d %k:%M:%S"`
echo "Scan Finish: ${CUR_DT}"
exit 0
