#!/bin/sh

# AliDDNS
# 使用 crontab 更新
# eg: 每10分钟检测一次. crontab -e
# */10 * * * * /usr/bin/aliddns >/dev/null 2>&1

# 必要的配置
##########################################
ak_id=''
ak_sec=''
main_dm=''
sub_dm=''
##########################################

intelnetip() {
    tmp_ip=`curl -sL --connect-timeout 3 http://ip.3322.net`
    if [ "Z$tmp_ip" == "Z" ]; then
        tmp_ip=`curl -sL --connect-timeout 3 http://members.3322.org/dyndns/getip`
    fi
    if [ "Z$tmp_ip" == "Z" ]; then
        tmp_ip=`curl -sL --connect-timeout 3 http://ip.42.pl/raw`
    fi
    if [ "Z$tmp_ip" == "Z" ]; then
        tmp_ip=`curl -sL --connect-timeout 3 http://whatismyip.akamai.com`
    fi
    echo -n $tmp_ip
}

nslookupip() {
    domain=$1
    dns=$2
    tmp_ip=`nslookup $domain $dns 2>/dev/null | sed '/^Server/,+1d; /#53$/d' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1`
    echo $tmp_ip
}

resolve2ip() {
    # resolve2ip domain<string>
    domain=$1
    tmp_ip=`nslookupip $domain ns1.alidns.com`
    if [ "Z$tmp_ip" == "Z" ]; then
        tmp_ip=`nslookupip $domain ns2.alidns.com`
    fi
    if [ "Z$tmp_ip" == "Z" ]; then
        tmp_ip=`nslookupip $domain 114.114.115.115`
    fi
    if [ "Z$tmp_ip" == "Z" ]; then
        tmp_ip=`curl -sL --connect-timeout 3 "119.29.29.29/d?dn=$domain"`
    fi
    echo -n $tmp_ip
}

log()
{
    logger -t aliddns $*
}

check_aliddns() {
    log "WAN-IP: ${ip}"
    if [ "Z$ip" == "Z" ]; then
        log "ERROR, cant get WAN-IP..."
        return 0
    fi
    current_ip=$(resolve2ip "$sub_dm.$main_dm")
    if [ "Z$current_ip" == "Z" ]; then
        rrid='' # NO Resolve IP Means new Record_ID
    fi
    log "DOMAIN-IP: ${current_ip}"
    if [ "Z$ip" == "Z$current_ip" ]; then
        log "IP needn't UPDATE."
        return 0
    else
        log "UPDATING..."
        return 1
    fi
}

urlencode() {
    # urlencode url<string>
    out=''
    for c in $(echo -n $1 | sed 's/[^\n]/&\n/g'); do
        case $c in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out$(printf '%%%02X' "'$c")" ;;
        esac
    done
    echo -n $out
}

send_request() {
    # send_request action<string> args<string>
    local args="AccessKeyId=$ak_id&Action=$1&Format=json&$2&Version=2015-01-09"
    local hash=$(urlencode $(echo -n "GET&%2F&$(urlencode $args)" | openssl dgst -sha1 -hmac "$ak_sec&" -binary | openssl base64))
    curl -sSL --connect-timeout 5 "http://alidns.aliyuncs.com/?$args&Signature=$hash"
}

get_recordid() {
    sed 's/RR/\n/g' | sed -n 's/.*RecordId[^0-9]*\([0-9]*\).*/\1\n/p' | sort -ru | sed /^$/d
}

query_recordid() {
    send_request "DescribeSubDomainRecords" "SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&SubDomain=$sub_dm.$main_dm&Timestamp=$timestamp"
}

update_record() {
    send_request "UpdateDomainRecord" "RR=$sub_dm&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&Timestamp=$timestamp&Type=A&Value=$ip"
}

do_ddns_record() {
    if [ "Z$rrid" == "Z" ]; then
        rrid=`query_recordid | get_recordid`
    fi
    if [ "Z$rrid" == "Z" ]; then
        # failed
        log "ERROR, Please Check SubDomain Exists."
    else
        update_record $rrid >/dev/null 2>&1
        log "UPDATE record $rrid"

        # save rrid
        log "$rrid" > /tmp/rrid
        log "UPDATED($ip)"
    fi
}


[ -x /usr/bin/openssl -a -x /usr/bin/curl -a -x /bin/sed ] ||
    ( log "Need [ openssl + curl + sed ]" && exit 1 )

rrid=$([ -f /tmp/rrid ] && cat /tmp/rrid)
ip=$(intelnetip)
DATE=$(date +'%Y-%m-%d %H:%M:%S')
timestamp=$(date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ")

check_aliddns || do_ddns_record
