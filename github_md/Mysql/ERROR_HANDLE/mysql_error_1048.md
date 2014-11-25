# Mysql Error 1048 奇遇记

>	Error: 1048 SQLSTATE: 23000 (ER_BAD_NULL_ERROR) Message: Column '%s' cannot be null 

[Mysql reference 5.6 error code](http://dev.mysql.com/doc/refman/5.6/en/error-messages-server.html#error_er_bad_null_error)

## 前提
----------
上周遇到次奇葩的同步错误，error 1048 ， 看似是简单的not null导致，但是为什么master可以执行，slave不行呢？为什么5.1的slave可以，5.6的slave不行呢？ 带着很多疑问，准备来一窥究竟

```
[ERROR] Slave SQL: Error 'Column 'type_id' cannot be null' on query. Default database: ''. Query: 'insert into if_dw_stats.da_upload_nh_score_rank_result(city_id,city_name,comm_id,region_name,paid,comm_name_nh,region_id_num,region_id,subregion_id_num,subregion_id,vcuv,vcuv_z,call_vcuv,call_vcuv_z,orders_vcuv,orders_vcuv_z,peitao,peitao_z,result_score,rank,type_id,type_name,pinyin,cal_dt) values (N), 其中N>9000;
```
这里总结一下我遇到过的错误，分三种情况,虽然都是由于null引起，但是1048才是重点。

  * **timestamp字段类型，为什么master执行成功，同步到slave报错？**
  * **int字段类型，5.1（master）<--- 5.6(slave)，同步报错？**
  * **int字段类型，5.6（master）<--- 5.6(slave)，同步报错？**    
  
接下来，开始进入主题

 
## 场景一

  * **explicit_defaults_for_timestamp** [timestamp注意事项](http://dev.mysql.com/doc/refman/5.6/en/server-system-variables.html#sysvar_explicit_defaults_for_timestamp)


```
* DB架构： Master(5.1) <-- Slave(5.6)
 
* 表结构如下 ：
dbadmin:abc> desc lc_time;
+-------+-----------+------+-----+-------------------+-----------------------------+
| Field | Type      | Null | Key | Default           | Extra                       |
+-------+-----------+------+-----+-------------------+-----------------------------+
| id    | timestamp | NO   |     | CURRENT_TIMESTAMP | on update CURRENT_TIMESTAMP |
+-------+-----------+------+-----+-------------------+-----------------------------+
1 row in set (0.00 sec)

* master

dbadmin:abc> select @@global.explicit_defaults_for_timestamp;
+------------------------------------------+
| @@global.explicit_defaults_for_timestamp |
+------------------------------------------+
|                                        0 |
+------------------------------------------+
1 row in set (0.00 sec)

	
dbadmin:abc> insert into lc_time values(null);
Query OK, 1 row affected (0.02 sec)

dbadmin:abc> select * from lc_time;
+---------------------+
| id                  |
+---------------------+
| 2014-11-25 13:02:14 |
+---------------------+
1 row in set (0.00 sec)	

*slave

dbadmin:abc> select @@global.explicit_defaults_for_timestamp;
+------------------------------------------+
| @@global.explicit_defaults_for_timestamp |
+------------------------------------------+
|                                        1 |
+------------------------------------------+
1 row in set (0.00 sec)

dbadmin:abc> insert into lc_time values(null);
ERROR 1048 (23000): Column 'id' cannot be null

 
 
``` 


* 结论：master上explicit_defaults_for_timestamp=0，slave上explicit_defaults_for_timestamp=1，会出现这种错误。

* 解决方案：
 
 	1. 保证master和slave explicit_defaults_for_timestamp 一致。
 	
 	2. 前端过滤掉null。


--------------------

## 场景二

  * **sql_mode**  [sql_mode 慎用](http://dev.mysql.com/doc/refman/5.6/en/data-type-defaults.html) 		

```
* DB架构
		master(5.1)
			| 
    ---------------------
    |					|	
  slave A(5.1)        slave B(5.6)
  

* 表结构

dbadmin:abc> show create table abc;
+-------+-----------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                |
+-------+-----------------------------------------------------------------------------------------------------------------------------+
| abc   | CREATE TABLE `abc` (
  `id` int(11) DEFAULT NULL,
  `id2` int(11) NOT NULL DEFAULT '6'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 |
+-------+-----------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)

* 核心参数： master 和 slave A，B 的sql_mode 都是 '';

* 症状：在master上执行一条SQL语句 insert into abc values(1,0),(1,null);
  结果 Slave A 正常， Slave B 报error 1048，Error 'Column 'id2' cannot be null' on query， 这是为什么呢？
  Question1：为什么insert into abc values(1,null)失败？insert into abc values(1,0),(1,null);成功？
  Question2：为什么5.1 slave可以，5.6slave 不行？
  Question3：手动去slave B上执行同样的insert，为什么可以执行成功？
  如果你已经知道为什么，可以忽略下面的分析。
       	
* 分析：
	细心的读者已经发现，第一个问题的答案已经在sql_mode链接中。接下来，测试过程中发现：insert into abc values(1,0),(1,null); 在sql_mode=''的时候，不管是5.1还是5.6都会成功执行。那么问题只有一个，sql_mode出了问题。查看master binlog后发现：在insert语句之前，多了这个可以执行的注释：SET @@session.sql_mode=2097152。我们来看看：

dbadmin:abc> SET @@session.sql_mode=2097152;
Query OK, 0 rows affected (0.00 sec)

dbadmin:abc> select @@session.sql_mode;
+---------------------+
| @@session.sql_mode  |
+---------------------+
| STRICT_TRANS_TABLES |
+---------------------+
1 row in set (0.00 sec)

这下，似乎发现了蛛丝马迹，那么问题又来了。

SET @@session.sql_mode=2097152; 从何而来？是程序写的？还是mysql自带的？
经过一番折腾，定位到此SQL来自java jdbc 。

以下代码摘自 java ConnectionIMPL.java

	private void setupServerForTruncationChecks() throws SQLException {
		if (getJdbcCompliantTruncation()) {
			if (versionMeetsMinimum(5, 0, 2)) {
				String currentSqlMode = 
					this.serverVariables.get("sql_mode");
				
				boolean strictTransTablesIsSet = StringUtils.indexOfIgnoreCase(currentSqlMode, "STRICT_TRANS_TABLES") != -1;
				
				if (currentSqlMode == null ||
						currentSqlMode.length() == 0 || !strictTransTablesIsSet) {
					StringBuffer commandBuf = new StringBuffer("SET sql_mode='");
					
					if (currentSqlMode != null && currentSqlMode.length() > 0) {
						commandBuf.append(currentSqlMode);
						commandBuf.append(",");
					}
					
					commandBuf.append("STRICT_TRANS_TABLES'");
					
					execSQL(null,  commandBuf.toString(), -1, null,
							DEFAULT_RESULT_SET_TYPE,
							DEFAULT_RESULT_SET_CONCURRENCY, false,
							this.database, null, false);
					
					setJdbcCompliantTruncation(false); // server's handling this for us now
				} else if (strictTransTablesIsSet) {
					// We didn't set it, but someone did, so we piggy back on it
					setJdbcCompliantTruncation(false); // server's handling this for us now
				}
				
			}
		}
	}



大致的意思就是：如果sql_mode = ‘’，那么java会调高sql_mode的级别，commandBuf.append("STRICT_TRANS_TABLES'");


ok，这下我们已经知道此set来自java，那么问题又来了。即便设置STRICT_TRANS_TABLES，要出问题，master就会报错了，为啥master是好的，Slave A是好的，却Slave B 同步出错呢？

结果已经很明显，因为Slave B是5.6。说的明显一点就是：
在严格模式下，5.1中可以执行，但是5.6不行，这应该算是5.6安全方面的新特性么？
有兴趣的同学可以自己测试下。 

``` 

* **解决方案**

	1. 配置java或者修改java源码，让其不要更改mysql的sql_mode
	2. 临时解决方案： insert ignore xxx；
	3. sql_mode的规范。

-----------------

## 场景三


* **来自case when的奇葩错误**

```
* DB架构   Master(5.6)  <--- Slave (5.6)
 
* sql_mode 都是'';

* 报错如下：

  Replicate_Wild_Ignore_Table: mysql.%,test.%
                   Last_Errno: 1048
                   Last_Error: Error 'Column 'referer' cannot be null' on query. Default database: 'action_db'. Query: 'insert into oplogin_log(`cityId`,`userId`,`userName`,`uri
`,`referer`,`logType`,`logDate`,`ip`,`status`)
              values('','','kyqxmxyt','/login.php?rtn=1','http://xx.com:80/login.php?rtn=' RLIKE (SELECT (CASE WHEN (ORD(MID((SELECT IFNULL(CAST(COUNT(DISTINCT(schema_na
me)) AS CHAR),0x20) FROM INFORMATION_SCHEMA.SCHEMATA),1,1))>50) THEN 0x687474703a2f2f6f70746f6f6c732e616e6a756b652e636f6d3a38302f6c6f67696e2e7068703f72746e3d ELSE 0x28 END)) AND 'ae
WZ'='aeWZ','1','1416020259','114.242.250.192','2') #v1:checklogin@login.php (15) 1416020259'

这条奇葩且牛B的SQL，我来稍微翻译一下，如果INFORMATION_SCHEMA.SCHEMATA 去重后，得到的库名的第一个字符如果是1，返回0，否则返回 null。

将这种SQL稍微转换成简单一点的：

master:abc> desc abc;
+-------+---------+------+-----+---------+-------+
| Field | Type    | Null | Key | Default | Extra |
+-------+---------+------+-----+---------+-------+
| id    | int(11) | YES  |     | NULL    |       |
| id2   | int(11) | NO   |     | 6       |       |
+-------+---------+------+-----+---------+-------+
2 rows in set (0.00 sec)

master:abc> select * from abc;
+------+-----+
| id   | id2 |
+------+-----+
|    1 |   0 |
|    1 |   0 |
|    2 |   0 |
|    2 |   0 |
|    1 |   1 |
|    1 |   0 |
+------+-----+
6 rows in set (0.00 sec)

master:abc> select * from lc;
Empty set (0.00 sec)	
   
   
master:abc> insert into abc values('1', case when (select count(*) from lc) < 1 then 1 else NULL end );
Query OK, 1 row affected (0.00 sec)

查看master的binlog如下：
*binlog*
# at 1109
#141125 12:44:51 server id 101082106  end_log_pos 1271 CRC32 0x9ec0ca94         Query   thread_id=28    exec_time=0     error_code=0
SET TIMESTAMP=1416890691/*!*/;
insert into abc values('1', case when (select count(*) from lc) < 1 then 1 else NULL end )
/*!*/;


slave:abc> select * from abc;
+------+-----+
| id   | id2 |
+------+-----+
|    1 |   0 |
|    1 |   0 |
|    2 |   0 |
|    2 |   0 |
|    1 |   0 |
|    1 |   0 |
+------+-----+
6 rows in set (0.00 sec)

slave:abc> select * from lc;
+------+
| id   |
+------+
|    1 |
|    2 |
|    3 |
+------+
3 rows in set (0.00 sec)

*slave status*
   Last_SQL_Errno: 1048
   Last_SQL_Error: Error 'Column 'id2' cannot be null' on query. Default database: 'abc'. Query: 'insert into abc values('1', case when (select count(*) from lc) < 1 then 1 else NULL end )'  



```

* **结论**

	1. 最终binlog并不是RBR，所以会报错。
	2. 临时解决方案： insert ignore xxx. 然后再用pt-table-checksum && pt-sync等修复。
	3. 禁止case when语句。











