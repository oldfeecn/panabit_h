# panabit_h

## linux iwan客户端脚本
1.从 https://github.com/oldfeecn/panabit_h/raw/refs/heads/main/linux_iwan/install_iwan.sh 下载iwan脚本,并移动到/etc/sdwan/目录下;赋予执行权限,并执行
2.install_iwan.sh判断 执行目录下是否有 linux_sdwand_x86 文件,如果存在,复制该文件并转移到 /etc/sdwan/ 目录下 更名为 iwan_panabit.sh ,给 iwan_panabit.sh 文件 执行权限,输出操作的日志
3.如果没有文件,从https://github.com/oldfeecn/panabit_h/raw/refs/heads/main/linux_iwan/linux_sdwand_x86 下载该文件,并转移到 /etc/sdwan/ 目录下 更名为 iwan_panabit.sh ,给 iwan_panabit.sh 文件 执行权限,输出操作的日志

4. 判断该目录下是否有iwan*.conf 配置文件;配置内容如下
/etc/sdwan/iwan.conf
虚拟网卡名称用中括号括起来[   ]
server      对端ip
username	登录账号名
password	密码
port		对端端口
mtu			最大传输单元
encrypt     加密：0为不加密，1为加密 【可选参数】
pipeid      管道ID，0为不带管道，管道取值1-1024 【可选参数】
pipeidx		管道方向，管道一端为0，另一端为1 【可选参数】

示例：
[iwan1]
server=10.10.1.11
username=wan2
password=123456
port=8001
mtu=1436
encrypt=0
pipeid=12
pipeidx=0

我需要一个shell脚本,默认打印出配置文件,并美化,加上注释,可以配置管理以上的值和文件脚本,以下是我的功能需求;
1.将该脚本添加到开机启动,如果系统已存在该脚本,则不添加,这段自己在 install_iwan.sh中实现,打印开启启动项的顺序和内容
2.判断 server 10.10.1.11 示例的路由在系统是否存在,如果不存在,添加该路由到物理网卡的默认网关路由,掩码32,如果有多个配置文件,则添加多个路由到物理网卡的默认网关路由,掩码32,并打印添加的日志
3.功能实现可以添加iwan接口,修改iwan接口名称,删除接口,其它配置内容同接口同步,按顺序实现,配置文件生成在/etc/sdwan/目录下,并打印日志,文件名为 接口名称.conf
4.添加完成后重启iwan服务,并打印日志
5.重启需要先关闭iwan服务,应该搜索 相关服务并kill掉进程
5.iwan 启动命令为 /etc/sdwan/iwan_panabit.sh -f /etc/sdwan/iwan*.conf &

我需要install_iwan.sh的具体实现

