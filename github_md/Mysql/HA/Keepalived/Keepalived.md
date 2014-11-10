* Keepalived for test

```
前提条件
1）机器A （master）
	real ip： 10.20.8.50
	vip：     10.20.8.188
2）机器B （slave）
	real ip： 10.20.8.27




测试用例：
0）模拟网络故障
	iptables -A INPUT -s $ip -j DROP
		a）添加规则，丢弃掉$ip的过来的icmp包
			eg：iptables -A INPUT -s 10.20.8.27 -j DROP
	iptables -D INPUT $id
		a）删除INPUT链中第$id个规则。
			eg：iptables -D INPUT 1
	iptables -L
		a) 查看iptables规则



网络故障：
	1）master 网卡failed， slave 网卡ok
		a) vip 成功漂移到slave.
	2）master 网卡ok，  slave 网卡failed
		a) vip 不会漂移。
	3）master 和 slave 网卡都ok，但是 master 和 slave 都互相ping不同。
		a）vip 也不会漂移。
	4）all failed
	结论：
	a）只要keepalived 开启，只要网卡没坏，不管网络层有什么样的限制，都不会影响vip的漂移。
	b）所以，vip的漂移只和 网卡，keepalived有关。

keepalived 故障：
	1）master keepalived  failed :  vip 成功漂移
	2）slave  keepalived  failed :  vip 不会漂移
	3）all failed ： vip不会漂移，但是master上的vip会消失。
	结论：
	a）只要master的keepalived stop，vip会消失。  当然，只要master上的keepalived start，vip又会马上起来。

mysql 故障：
	1）master mysqld failed
		a) master mysqld stop， vip会成功漂移。 因为mysqld stop，意味着keepalived stop { 请参考keepalived故障 }
	2）slave  mysqld failed
		a) slave mysqld stop， vip不会漂移。  因为mysqld stop，意味着keepalived stop  { 请参考keepalived故障 }
	3）all failed
		不会漂移。


遇到的坑：
1）在idc20 用ifconfig eth0:1 10.20.8.188 添加vip,会默认添加一条路由 10.0.0.0 0.0.0.0 255.0.0.0 U 0 0 0 eth0

路由规则：db20-024
10.2.1.0        0.0.0.0         255.255.255.0   U     0      0        0 eth2
10.20.8.0       0.0.0.0         255.255.255.0   U     0      0        0 eth0
169.254.0.0     0.0.0.0         255.255.0.0     U     0      0        0 eth2
10.0.0.0 		0.0.0.0 		255.0.0.0 		U 	  0 	 0 		  0 eth0   -- 自动添加
0.0.0.0         10.20.8.1       0.0.0.0         UG    0      0        0 eth0

	解决方案： ifconfig eth0:1 10.20.8.188/24
	keepalive 配置中：
		virtual_ipaddress {
		10.20.8.188/24 dev eth0 label eth0:1 #定义VIP，并制定设备和别名
		}


2）如果你再master上面配置了ifcfg-eth0:1,那么在master上 ifdown eth0 , 然后再 ifup eth0 ,那么 master和slave两边都会出现vip。
	解决方案： 配置keepalived HA时候，不要写ifcfg-eth0:1 文件即可。

3）如何暂停HA功能一小时。
	一般做法：
		a）先停掉slave上的keepalived
		b）然后再停掉master上的keepalived  --危险
	但是：
		如果停掉了master上的keepalived，那么master的vip就会消失，会影响业务。
	所以正确的做法是：
		a）只要停掉slave上的keepalived进程即可。

```
