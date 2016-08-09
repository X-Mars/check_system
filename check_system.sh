#!/bin/bash
IP=`ifconfig |grep inet|head -1|awk '{print $2}'|awk -F: '{print $2}'`

#创建日志存放目录
DIRECTORY="/var/log/xunjian"
LOGS="$DIRECTORY/log"
SHA1CACHE="$DIRECTORY/sha1"
TMP="$DIRECTORY/tmp"
JIANCESHIJIAN=5

HOSTNAME=`hostname`
echo $HOSTNAME
DATE=`date +%m月%d日-%H:%M:%S`


touch -t $(date -d "$JIANCESHIJIAN min ago" +%Y%m%d%H%M) $TMP/time.tmp

########################文件修改监控#############################

function CheckFileSha1()
 {
 NAME=$1
 FILE=$2
 #echo $1 $2
 if [ ! -f $SHA1CACHE/${NAME}_sha1 ];then
	sha1sum $FILE |awk '{print $1}' >> $SHA1CACHE/${NAME}_sha1
 fi
	
	#获取现有sha1
	SHA1=`sha1sum $FILE |awk '{print $1}'`

	#读取原有sha1
	LAST_SHA1=`cat $SHA1CACHE/${NAME}_sha1`

	#新旧sha1进行比对
	if [ $SHA1 != $LAST_SHA1 ];then
		touch -a $TMP/${NAME}_time.tmp
			if [ $TMP/time.tmp -ot $TMP/${NAME}_time.tmp ];then
				echo "文件刚刚被修改:${FILE} " >> $LOGS/$HOSTNAME.log
#				echo $FILE
			else
				echo $SHA1 > $SHA1CACHE/${NAME}_sha1
					rm -f $TMP/${NAME}_time.tmp
			fi
	fi
 }

 CheckFileSha1 passwd "/etc/passwd" 
 
 CheckFileSha1 profile "/etc/profile"

 CheckFileSha1 rc "/etc/rc.local"
 
########################目录下文件修改监控##########################
 
function CheckDirSha1()
 {
 NAME=$1
 FILE=$2
 #echo $1 $2
 if [ ! -f $SHA1CACHE/${NAME}_sha1 ];then
	sha1sum $FILE/* >> $SHA1CACHE/${NAME}_sha1
 fi

#获取现有sha1
sha1sum $FILE/* >> $SHA1CACHE/${NAME}_sha1_new

DIFF=`diff $SHA1CACHE/${NAME}_sha1_new $SHA1CACHE/${NAME}_sha1 |awk '{print $3}' |sort |uniq |sed 1d`

if [ -n  "$DIFF" ];then
	touch -a $TMP/${NAME}_time.tmp
		if [ $TMP/time.tmp -ot $TMP/${NAME}_time.tmp ];then
			echo "文件刚刚被修改:$DIFF" >> $LOGS/$HOSTNAME.log
#			echo $DIFF
		else
			rm -f $SHA1CACHE/${NAME}_sha1
			sha1sum $FILE/* >> $SHA1CACHE/${NAME}_sha1
			rm -f $TMP/${NAME}_time.tmp
		fi
fi
rm -f $SHA1CACHE/${NAME}_sha1_new

 }
 
CheckDirSha1 profile_d "/etc/profile.d"

CheckDirSha1 sbin "/sbin"

CheckDirSha1 usr_bin "/usr/bin"

CheckDirSha1 usr_sbin "/usr/sbin"

CheckDirSha1 glassfish_bin "/usr/local/glassfish4/bin"

CheckDirSha1 jdk_bin "/usr/local/jdk/bin"

CheckDirSha1 crontab "/var/spool/cron"
 
 
#####.ssh################

#通过/etc/passwd获取所有用户的家目录
for ssh_DIRECTORY in `cat /etc/passwd |awk -F ":" '{print $6}' |grep -vw /`
do
	SSH_DIRECTORY=$ssh_DIRECTORY/.ssh
	
	#家目录下的.ssh目录内，生成时间 较 对比文件生成时间 晚 的文件
	if [ -d "$SSH_DIRECTORY" ];then
		SSH_CHANGE=`find $SSH_DIRECTORY -newer $TMP/time.tmp`
		if [ -n "$SSH_CHANGE" ];then
			echo "文件刚刚被修改:$SSH_CHANGE" >> $LOGS/$HOSTNAME.log
			
		fi
	fi
done

########################进程检测#################################

#获取原有进程列表，并保存到default_process
if [ ! -f $DIRECTORY/default_process ];then
	ps -A |awk '{print $4}' | sort -u | sed '$a\egrep' | sed '$a\xunjian_ansible'  | sed '$a\anacron' |sed '$a\sh' | sed 's/$/|/' | awk '{printf $0}' |sed 's/^/|&/g'|sed 's/^/"&/g' |sed 's/$/"/g' > $DIRECTORY/default_process
fi
DEFAULT_PROCESS=`cat $DIRECTORY/default_process`

#获取现有进程并与原有进程比对
UNKNOWN_PROCESS=`ps -A |awk '{print $4}' | sort -u |egrep -v $DEFAULT_PROCESS`

if [ -n "$UNKNOWN_PROCESS" ];then
	touch -a $TMP/process_time.tmp
		if [ $TMP/time.tmp -ot $TMP/process_time.tmp ];then
			echo "有未知进程启动:$UNKNOWN_PROCESS" >> $LOGS/$HOSTNAME.log
			ps -ef|grep $UNKNOWN_PROCESS |sort |uniq >> $LOGS/$HOSTNAME-xiangxi.log
		else
#			ps -A |awk '{print $4}' | sort -u | sed '$a\egrep' | sed '$a\xunjian_ansible'  | sed '$a\anacron' | sed 's/$/|/' | awk '{printf $0}' |sed 's/^/|&/g'|sed 's/^/"&/g' |sed 's/$/"/g' > $DIRECTORY/default_process
			rm -f $TMP/process_time.tmp
		fi
fi

#########################新增端口监控############################

#获取原有端口，并保存到default_port文件
if [ ! -f $DIRECTORY/default_port ];then
	netstat -ntupl|grep LISTEN|awk '{print $4}'|awk -F ":" '{print $2,$4}' |sed s/[[:space:]]//g |sort |uniq |sed 's/$/|/' |awk '{printf $0}' |sed 's/^/|&/g' |sed 's/^/"&/g' |sed 's/$/"/g' > $DIRECTORY/default_port
fi
DEFAULT_PORT=`cat $DIRECTORY/default_port`

LISTEN_PORT=`netstat -ntupl|grep LISTEN|awk '{print $4}'|awk -F ":" '{print $2,$4}'|sed s/[[:space:]]//g|sort |uniq`

#获取现有端口并与原有端口比对
NEW_PORT=`netstat -ntupl|grep LISTEN|awk '{print $4}'|awk -F ":" '{print $2,$4}'|sed s/[[:space:]]//g|sort |uniq|egrep -v "$DEFAULT_PORT"`

#echo $NEW_PORT
if [ -n "$NEW_PORT" ];then
	touch -a $TMP/port_time.tmp
		if [ $TMP/time.tmp -ot $TMP/port_time.tmp ];then
			echo "有新端口被监听:$NEW_PORT" >> $LOGS/$HOSTNAME.log
		else
			netstat -ntupl|grep LISTEN|awk '{print $4}'|awk -F ":" '{print $2,$4}' |sed s/[[:space:]]//g |sort |uniq |sed 's/$/|/' |awk '{printf $0}' |sed 's/^/|&/g' |sed 's/^/"&/g' |sed 's/$/"/g' > $DIRECTORY/default_port
			rm -f $TMP/port_time.tmp
		fi
fi

###############chkconfig##########

#获取原有开机启动项，并保存到default_chkconfig
if [ ! -f $DIRECTORY/default_chkconfig ];then
	chkconfig | grep :on |awk '{print $1}'|sed 's/$/|/' | awk '{printf $0}' |sed 's/^/|&/g'|sed 's/^/"&/g' |sed 's/$/"/g' > $DIRECTORY/default_chkconfig
fi
DEFAULT_CHKCONFIG=`cat $DIRECTORY/default_chkconfig`

#获取现有开机启动项，并与原启动项比对
UNKNOWN_CHKCONFIG=`chkconfig | grep :on |awk '{print $1}' |egrep -v $DEFAULT_CHKCONFIG`
if [ -n "$UNKNOWN_CHKCONFIG" ];then
	touch -a $TMP/chk_time.tmp
		if [ $TMP/time.tmp -ot $TMP/chk_time.tmp ];then
			echo "新增chkconfig启动项:$UNKNOWN_CHKCONFIG" >> $LOGS/$HOSTNAME.log
#			echo $UNKNOWN_CHKCONFIG
		else
			chkconfig | grep :on |awk '{print $1}'|sed 's/$/|/' | awk '{printf $0}' |sed 's/^/|&/g'|sed 's/^/"&/g' |sed 's/$/"/g' > $DIRECTORY/default_chkconfig
			rm -f $TMP/chk_time.tmp
		fi
fi

if [ -f $LOGS/$HOSTNAME.log ];then
	sed -i 's/^/'$HOSTNAME'|'$IP'|'$DATE'|/' $LOGS/$HOSTNAME.log
#	sed -i '1i主机名|IP|时间|事件' $LOGS/$HOSTNAME.log
#	sed -i '1i\主机名:'$HOSTNAME' IP:'$IP' \\'n''	$LOGS/$HOSTNAME.log
fi
rm -f $TMP/time.tmp

