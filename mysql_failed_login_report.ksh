#!/bin/ksh

############################################################
## Script:  mysql_failed_login_report.ksh
##
## Purpose: The purpose of this script is to report on the 
##          MySQL Servers that had failed login attempts
##
## Syntax:  mysql_failed_login_report.ksh < Option 1 > [ < Start DT > < End DT > ]
##
## Dependencies: None
##
## Input:       Option 1  -> [ 'ALL' | BLANK ]                        - Report on all available MySQL Servers
##                           '<Shard>'                                - Report on all available MySQL Servers associated with the given shard
##              Start DT  -> MM/DD/YY                                 - Report start date
##              End DT    -> MM/DD/YY                                 - Report end date
## Output:      None
##
## History:
## Date        Developer     Information
## ----------  ------------  -------------------------------
## 04/22/2014  J. Jokuti     Initial Release
## 02/03/2015  J. Jokuti     Modified code to use riot_sgdb database tables
##
## COPYRIGHT 2014 BY RIOT GAMES. ALL RIGHTS RESERVED.
############################################################
BASENAME=`basename $0`
OPTION1=${1}
START_DT=${2}
END_DT=${3}

SUBJECT="MySQL Servers - Failed Login Report"

PROCESS_ERROR="WARNING: Another ${BASENAME} ${OPTION1} process is still running. This currently running process is being aborted."
SQL_DOWN_ERROR="ERROR: The DBADMIN1 MySQL Server is not running."
NO_SERVERS_ERROR="ERROR: There were no MySQL Servers selected for the failed login report."

TMPSQL="/var/tmp/tmp_sql_$$"
TMPOUT="/var/tmp/tmp_out_$$"
TMPSERVERS="/var/tmp/tmp_servers_$$"
TMPMSG="/var/tmp/tmp_msg_$$"
NOREPLY_ADDR="noreply@riotgames.com"
DBA_EMAIL_ADDR="DBA@riotgames.com"

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
    PROC_FLAG=`ps -ef | grep ${BASENAME} | egrep -v "grep" | wc -l`

    if [ ${PROC_FLAG} -gt 3 ];
    then
        echo "${PROCESS_ERROR}" | mail -s "${SUBJECT}" "${DBA_EMAIL_ADDR}" -- -F "MySQL Server" -f ${NOREPLY_ADDR}

        exit 1
    fi

    return 0
}

############################################################
##
## Function: verify_mysql_servers
##
## Query the DBADMIN1 MySQL Server to verify the server list
##
############################################################
verify_mysql_servers()
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
        echo "SELECT CONCAT('SERVERS: ', CAST(COUNT(*) AS CHAR)) AS INFO" > ${TMPSQL}
        echo "  FROM riot_sgdb.riot_servers s " >> ${TMPSQL}
        echo "  JOIN riot_sgdb.failed_logins_scan_dt_range sr " >> ${TMPSQL}
        echo "    ON sr.ip_addr = s.ip_addr " >> ${TMPSQL}
        echo " WHERE s.status = 'A' " >> ${TMPSQL}
        echo "   AND s.port_nbr = 3306; " >> ${TMPSQL}
    else 
        ### Input Argument: Shard
        INPUT_LEN=`echo ${1} | wc -L`
        if [ ${INPUT_LEN} -le 5 ];
        then
            echo "SELECT CONCAT('SERVERS: ', CAST(COUNT(*) AS CHAR)) AS INFO" > ${TMPSQL}
            echo "  FROM riot_sgdb.riot_servers s " >> ${TMPSQL}
            echo "  JOIN riot_sgdb.riot_server_regions r " >> ${TMPSQL}
            echo "    ON r.ip_addr = s.ip_addr " >> ${TMPSQL}
            echo "   AND r.port_nbr = s.port_nbr " >> ${TMPSQL}
            echo "  JOIN riot_sgdb.riot_shards d " >> ${TMPSQL}
            echo "    ON d.region_id = r.region_id " >> ${TMPSQL}
            echo "  JOIN riot_sgdb.failed_logins_scan_dt_range sr " >> ${TMPSQL}
            echo "    ON sr.ip_addr = s.ip_addr " >> ${TMPSQL}
            echo " WHERE d.shard_name = '${1}' " >> ${TMPSQL}
            echo "   AND s.status = 'A' " >> ${TMPSQL}
            echo "   AND s.port_nbr = 3306 " >> ${TMPSQL}
            echo "   AND d.status = 'A'; " >> ${TMPSQL}
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

    SERVER_CNT=`grep SERVERS ${TMPSERVERS} | cut -f2 -d' '`
    if [ ${SERVER_CNT} -eq 0 ];
    then
        printf "${NO_SERVERS_ERROR}\n\nSQL Statement:\n" > ${TMPMSG}
        cat ${TMPSQL} >> ${TMPMSG}
        cat ${TMPMSG} | mail -s "${SUBJECT}" "${DBA_EMAIL_ADDR}" -- -F "`echo ${HOSTNAME} | tr '[:lower:]' '[:upper:]'` MySQL Server" -f ${NOREPLY_ADDR}
        rm -f ${TMPSQL} ${TMPSERVERS} ${TMPMSG}
        exit 4
    fi

    rm -f ${TMPSQL} ${TMPSERVERS} 

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
send_report()
{
    if [ "${2}" = "" ];
    then
        ST_DT=`date "+%y%m%d 00:00:00" --date="7 days ago"`
        EN_DT=`date "+%y%m%d 23:59:59" --date="1 day ago"`
    else
        date "+%d/%m/%y" -d "${2}" 2>1 > /dev/null
        IS_VALID=$?

        if [ ${IS_VALID} -eq 0 ];
        then
            ST_DT=`date "+%y%m%d 00:00:00" -d "${2}"`

            if [ "${3}" = "" ];
            then
                EN_DT=`date "+%y%m%d 23:59:59" --date="1 day ago"`
            else
                date "+%d/%m/%y" -d "${3}" 2>1 > /dev/null
                IS_VALID=$?

                if [ ${IS_VALID} -eq 0 ];
                then
                    EN_DT=`date "+%y%m%d 23:59:59" -d "${3}"`
                else
                    EN_DT=`date "+%y%m%d 23:59:59" --date="1 day ago"`
                fi
            fi
        else
            ST_DT=`date "+%y%m%d 00:00:00" --date="7 days ago"`
            EN_DT=`date "+%y%m%d 23:59:59" --date="1 day ago"`
        fi
    fi

    ### Input Argument: Shard
    if ! [ "${1}" = "" ] && ! [ "${1}" = "ALL" ];
    then
        echo "SELECT CONCAT('<div align=\"center\">', d.shard_name, '</div>') AS shard_name," > ${TMPSQL}
        echo "       CONCAT('<div align=\"center\">', s.server_name, '</div>') AS server_name," >> ${TMPSQL}
        echo "              CONCAT('<div align=\"center\">', h.ip_addr, '</div>') AS ip_addr," >> ${TMPSQL}
        echo "              CONCAT('<div align=\"center\">', h.user, '</div>') AS user," >> ${TMPSQL}
        echo "              CONCAT('<div align=\"center\">', h.host, '</div>') AS host," >> ${TMPSQL}
        echo "              CONCAT('<div align=\"center\">', IFNULL(SUBSTRING('YES', SIGN(CHAR_LENGTH(n.ip_addr))), ' '), '</div>') AS sec_server," >> ${TMPSQL}
        echo "              CONCAT('<div align=\"center\">', CAST(SUM(h.fail_cnt) AS CHAR), '</div>') AS fail_cnt" >> ${TMPSQL}
        echo "         FROM riot_sgdb.failed_logins_history h" >> ${TMPSQL}
        echo "         JOIN riot_sgdb.riot_servers s" >> ${TMPSQL}
        echo "           ON s.ip_addr = h.ip_addr" >> ${TMPSQL}
        echo "         JOIN riot_sgdb.riot_server_regions r " >> ${TMPSQL}
        echo "           ON r.ip_addr = s.ip_addr " >> ${TMPSQL}
        echo "          AND r.port_nbr = s.port_nbr " >> ${TMPSQL}
        echo "         JOIN riot_sgdb.riot_shards d " >> ${TMPSQL}
        echo "           ON d.region_id = r.region_id " >> ${TMPSQL}
        echo "         LEFT JOIN riot_sgdb.nexpose_servers n" >> ${TMPSQL}
        echo "           ON n.ip_addr = h.host" >> ${TMPSQL}
        echo "        WHERE h.log_dt >= STR_TO_DATE('${ST_DT}', '%y%m%d %k:%i:%s')" >> ${TMPSQL}
        echo "          AND h.log_dt <= STR_TO_DATE('${EN_DT}', '%y%m%d %k:%i:%s')" >> ${TMPSQL}
        echo "          AND s.port_nbr = 3306" >> ${TMPSQL}
        echo "          AND d.shard_name = '${1}'" >> ${TMPSQL}
        echo "          AND s.status = 'A' " >> ${TMPSQL}
        echo "          AND d.status = 'A' " >> ${TMPSQL}
        echo "        GROUP BY d.shard_name, s.server_name, h.ip_addr, h.user, h.host" >> ${TMPSQL}
        echo "        ORDER BY d.shard_name, s.server_name, h.user, h.host;" >> ${TMPSQL}
    fi


    mysql --user=scanuser --password='************' --connect-timeout=15 --host=dbadmin1 < ${TMPSQL} > ${TMPOUT}

    OUT_FLAG=`cat ${TMPOUT} | wc -l`

    if [ ${OUT_FLAG} -gt 0 ];
    then
        echo "<html><body>" > ${TMPMSG}
        echo "<H3>Failed login attempts detected for the days `date "+%m/%d/%y" -d "${ST_DT}"` thru `date "+%m/%d/%y" -d "${EN_DT}"`</H3>" >> ${TMPMSG}

        echo "<table style=\"width: 770px;\" border=0> <col width=\"100\"> <col width=\"130\"> <col width=\"100\"> <col width=\"130\"> <col width=\"100\"> <col width=\"110\"> <col width=\"100\">" >> ${TMPMSG}
        echo "<tr><th>Shard</th><th>Server</th><th>IP Address</th><th>User Name</th><th>User Host</th><th>Security Scan</th><th>Failure Cnt</th></tr>" >> ${TMPMSG}

        cat ${TMPOUT} | sed 's/^/<tr><td>/g' | sed 's/$/<\/td><\/tr>/g' | sed 's/\t/<\/td><td>/g' | tail -n+2 >> ${TMPMSG}
        echo "</table>" >> ${TMPMSG}
        echo "</body></html>" >> ${TMPMSG}

        cat ${TMPMSG} | mail -s "$(echo -e "${1} ${SUBJECT}\nContent-Type: text/html")" "${DBA_EMAIL_ADDR}" -- -F "MySQL Server" -f ${NOREPLY_ADDR}

        rm -f ${TMPSQL} ${TMPOUT} ${TMPMSG}
    fi

    return 0
}

############################################################
##
## Main Body
##
############################################################
check_process

verify_mysql_servers "${OPTION1}"

send_report "${OPTION1}" "${START_DT}" "${END_DT}"

exit 0
