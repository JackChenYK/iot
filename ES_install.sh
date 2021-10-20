#!/bin/bash
cd `dirname $0`
install_path=`pwd`

#判断es用户
user=`whoami`
echo "..."${user}
#删除elasticsearch进程
pidLc=`ps -ef|grep elasticsearch |grep -v grep |awk '{print $2}'|wc -l`

if [[ $pidLc ]];then
	for i in `ps -ef|grep elasticsearch |grep -v grep |awk '{print $2}'`;
	do
		pid_user=`ps -aux|grep ${i} |grep -v grep |awk '{print $1}'`;
		if [ ${user} != "root" ] && [ ${user} != ${pid_user} ];then
			echo "elasticsearch pid is alread exists,${user} has no permission kill it,please kill it first"
			exit
		fi
		echo 'kill pid '${i};
		kill -9 $i;
	done
	echo 'elasticsearch pid is killed!'

fi

#判断当前目录是否具有操作权限

path=`pwd`
if [ -w "${path}" ] && [ -x "${path}" ];then
        echo "modify privileages ...."
else
        echo "Permission denied,please conntact administrator to add permission!"
        exit 0;
fi



#判断安装类型
echo "please input install type:(1:classic;2:custom,please input 1 or 2,default:1)"
read install_type
if [ ! ${install_type} ];then
	install_type=1
fi

#installType=1
#本机IP
echo "please input the node's ip:"
read ipAddr
while [ ! ${ipAddr} ];
do
	read ipAddr
done
	
if [ ${install_type} == 2 ];then
	if [ ${user} == 'root' ];then
		echo "please input a common user for elasticsearch:(default "esuser")"
		read esuser

		if [ ! ${esuser} ];then
			esuser="esuser"
		fi
	fi
	
	echo 'please input elasticsearch type:(1:single,2:cluster,default 1)'
	read installType

	while [ ! ${installType} ]
	do
        read  installType
	done


	function localInfo(){
			echo -e "please input username(default:uinnova)"
			read localusername
			if [ ! ${localusername} ];then
				localusername="uinnova"
			fi
			
			echo -e "please input password(default:Uinnova@123)"
			read localpassword
			if [ ! ${localpassword} ];then
				localpassword="Uinnova@123"
			fi
	}

	if [ ${installType} -eq 1 ];then
		localInfo
	else
        localInfo
        #集群ip
        echo "please input unicast.hosts,like(192.168.1.1,192.168.1.2):"
        read hostList

        #拼接unicast.hosts字符串
        OLD_IFS="$IFS"
        #echo "---------"
        #echo "OLD_IFS="${OLD_IFS}
        IFS=","
        arr=(${hostList})
        IFS="$OLD_IFS"
        #echo "current :"${OLD_IFS}
        #echo "=========="

        str=""
        for s in ${arr[@]}
        do
        #set -x
                #echo "$s"
                str+="\"$s\","
        #set +x
        done
        hostList=${str%?}
        #echo ${hostList}

	fi
else
	localusername="uinnova"
	localpassword="Uinnova@123"
	installType=1
	esuser="esuser"
fi

#启动
	if [ ${user} == 'root' ];then
		id ${esuser} >& /dev/null
		if [ $? -ne 0 ]
		then
			useradd ${esuser}
		fi
	
		ulimitn=`su ${esuser} -c "ulimit -n"`
		ulimitu=`su ${esuser} -c "ulimit -u"`
		maxmapcount=`su ${esuser} -c "cat /proc/sys/vm/max_map_count"`
	
		info=`su ${esuser} -c "java -version 2>&1 | sed '1!d' | sed -e 's/\"//g' -e 's/version//' | sed -e 's/\"//g' -e 's/java//'  |awk '{print $2}'"`
	
	else
		info=`java -version 2>&1 | sed '1!d' | sed -e 's/\"//g' -e 's/version//' | awk '{print $2}'`
		ulimit -n 65536
		ulimit -u 65536
		ulimitn=`ulimit -n`
		ulimitu=`ulimit -u`
		maxmapcount=`cat /proc/sys/vm/max_map_count`
	fi

	if [[ ${ulimitn} < 65536 ]] || [[ ${ulimitu} < 65536 ]] || [[ ${maxmapcount} < 262144 ]];then
		echo "environment is not be set!"
		echo "open files is: "${ulimitn}
		echo "max user processes: "${ulimitu}
		echo "vm.map_map_count: "${maxmapcount}
		exit
	fi

	if [[ ${info} =~ 'java' ]];then
		echo "jdk is not exist,please install jdk!"
		exit
	fi

	echo ${info%_*} > tmp.txt
	echo '1.8' >>tmp.txt

	cat tmp.txt |sort >> tmp2.txt

	curVer=`awk 'NR==1{print $1}' tmp2.txt`
	echo ${curVer}


	if [[ ${curVer} =~ '1.8' ]];then
		echo "jdk version is "${curVer}
	else
		echo "jdk version is not support,please install jdk!"
		exit
	fi

	rm -rf tmp*.txt

#elasticsearch安装目录
esDir=`pwd`
cd ${esDir}


#解压
rm -rf elasticsearch
tar xf elasticsearch-6.6.2.tar.gz
mv elasticsearch-6.6.2  elasticsearch
if [ ${user} == 'root' ];then
	chown -R ${esuser} elasticsearch
fi


#修改配置

totalMem=`awk '($1 == "MemTotal:"){print int($2/1048576/2+0.99)}' /proc/meminfo`
sed -i 's/-Xms.*/-Xms'${totalMem}'g/g' elasticsearch/config/jvm.options
sed -i 's/-Xmx.*/-Xmx'${totalMem}'g/g' elasticsearch/config/jvm.options

sed -i 's/\#network.host.*/network.host: '${ipAddr}'/g' elasticsearch/config/elasticsearch.yml
sed -i 's#\#cluster.name.*#cluster.name: tarsier#g' elasticsearch/config/elasticsearch.yml
sed -i 's#\#node.name.*#node.name: tarsier-'${ipAddr}'#g' elasticsearch/config/elasticsearch.yml
sed -i '$a\indices.query.bool.max_clause_count: 2000' elasticsearch/config/elasticsearch.yml
sed -i 's#\#bootstrap.memory_lock.*#bootstrap.memory_lock: false#g' elasticsearch/config/elasticsearch.yml
sed -i '/bootstrap.memory_lock: false/a\bootstrap.system_call_filter: false' elasticsearch/config/elasticsearch.yml

if [ ${installType} == 2 ];then
		sed -i "s/\#discovery.zen.ping.unicast.hosts: .*/discovery.zen.ping.unicast.hosts: [${hostList}]/g" elasticsearch/config/elasticsearch.yml
		sed -i "s/\#discovery.zen.minimum_master_nodes: .*/discovery.zen.minimum_master_nodes: 2/g" elasticsearch/config/elasticsearch.yml
fi

sed -i '$a\xpack.security.enabled: false' elasticsearch/config/elasticsearch.yml
sed -i '$a\http.basic.enabled: true' elasticsearch/config/elasticsearch.yml
sed -i '$a\http.basic.log: false' elasticsearch/config/elasticsearch.yml
sed -i '$a\http.basic.username: '${localusername}'' elasticsearch/config/elasticsearch.yml
sed -i '$a\http.basic.password: '${localpassword}'' elasticsearch/config/elasticsearch.yml


#启动
if [ ${user} == 'root' ];then
        su ${esuser} -c "elasticsearch/bin/elasticsearch -d"
else
        elasticsearch/bin/elasticsearch -d

fi

echo "wait for 1 min to start elasticsearch...."
sleep 60

pid=`ps -ef|grep elasticsearch | grep -v grep |wc -l`

if [ ! ${pid} ];then
        echo "elasticsearch installed failed,please try again!"
else
        echo "elasticsearch installed successfully!"
        ps -ef|grep elasticsearch |grep -v grep
fi
if [ ${install_type} == 1 ];then
	echo "the user of elasticsearch is: uinnova"
	echo "the password of elasticsearch is:Uinnova@123"
fi
