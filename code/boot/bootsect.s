.code16

# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 192kB, more than enough for current
# versions of linux
# SYS_SIZE是要加载的系统模块长度，单位是节，每节16字节。0x3000共为0x30000字节=196KB。
# 若以1024字节为1KB计，则因该就192KB。对应当前内核版本这个空间长度已足够了。当该值为
# 0x8000时，表示内核最大为512KB。因为内存0x90000处开始存放移动后的bootsect和setup的代码，
# 因此该值最大不得超过0x9000（表示584KB）。
#
# 头文件linux/config.h中定义了内核用到的一些常数符号和Linus自己使用的默认硬盘参数块。
# 例如定义了以下一些常数：
# DEF_INITSEG	0x9000							//引导扇区程序将被移动到得段值。
# DEF_SYSSEG	0x1000							//引导扇区程序把系统模块加载到内存的段值。
# DEF_SETUPSEG	0x9020							//setup程序所处内存段位置。
# DEF_SYSSIZE	0x3000							//内核系统模块默认最大节数（16字节=1节）。

#include <linux/config.h>

.equ 	SYSSIZE, DEF_SYSSIZE		# system模块的长度
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.

# bootsect.S被ROM BIOS启动子程序加载至0x7c00（32KB）处，并将自己移到了地址0x90000
# （576KB）处，并跳转至那里。
#
# 它然后使用BIOS中断将'setup'直接加载到自己的后面（0x90200）（576.5KB），并将system
# 加载到地址0x10000处。
#
# 注意！目前的内核系统最大长度限制为（8*65536）（512KB）B，即使是在将来这也应该没有问题
# 的。我想让他保持简单明了。这样512KB的最大内核长度应该足够了，尤其是这里没有像MINIX中
# 一样包含缓冲区高速缓冲。

# globl 表明标识符是全局的，使得符号对连接器可见，变为对整个工程可用的全局变量

.global _start, begtext, begdata, begbss, endtext, enddata, endbss

# .text, .data, .bss 分别定义当前代码段、数据段和未初始化数据段。
# 在链接 多个目标模块时，链接程序 ld86 会根据它们的类别把各个目标模块中的相应段
# 分别组合在一起。这里把三个段都定义在同一重叠地址范围中，因此本程序实际上不分段。

.text
begtext:
.data
begdata:
.bss
begbss:
.text

.equ 	SETUPLEN, 4			# nr of setup-sectors(256*4=1024) # setup程序的扇区数为4块
.equ 	BOOTSEG,  0x07c0		# original address of boot-sector # bootset的段地址为0x07c0
.equ 	INITSEG,  DEF_INITSEG		# we move boot here - out of the way # 把bootset移到0x9000
.equ 	SETUPSEG, DEF_SETUPSEG		# setup starts here # setup程序就是从0x9020开始执行
.equ 	SYSSEG,   DEF_SYSSEG		# system loaded at 0x10000 (65536). # system模块加载到0x10000
.equ 	ENDSEG,   SYSSEG + SYSSIZE	# where to stop loading # 停止加载

# 源代码中的ROOT_DEV=0x306表示第二个硬盘的第一个分区，设备号 = 主设备号 * 256 + 次设备号（dev_no = (major << 8) + minor）
# 主设备号定义：1-内存，2-磁盘，3-硬盘，4-ttyx，5-tty，6-并行口，7-非命名管道
# ROOT_DEV:	0x000 - same type of floppy as boot.
#           0x300	/dev/hd0	系统中第一个硬盘
#           0x301 - first partition on first drive etc	# 系统中第一个硬盘的第一分区
#           0x302	/dev/hd2	系统中第一个硬盘的第二分区
#           0x303	/dev/hd3	系统中第一个硬盘的第三分区
#           0x304	/dev/hd4	系统中第一个硬盘的第四分区
#           0x305	/dev/hd5	系统中第二个硬盘
#           0x306 - first partition on second drive etc
#           0x307	/dev/hd7	系统中第二个硬盘的第二分区
#           0x308	/dev/hd8	系统中第二个硬盘的第三分区
#           0x309	/dev/hd9	系统中第二个硬盘的第四分区
# ROOT_DEV & SWAP_DEV are now written by "build".
.equ 	ROOT_DEV, 0x0
.equ 	SWAP_DEV, 0x0

# bootsect.s 入口地址
# 1.首先加载bootsect的代码（磁盘引导块程序，在磁盘中第一个扇区的程序）
# 2.将setup.s中代码加载到bootsect.s中代码之后
# 3.将system模块加载到0x10000地方，最后跳转到setup.s中运行

	ljmp	$BOOTSEG, $_start	# 标准化起始地址 EA 05 00 C0 07 ljmp 0x07c0:0005
_start:
# step1. 复制自身到 INITSEG(0x9000:0000)
	mov		$BOOTSEG, %ax
	mov		%ax, %ds		# 将ds段寄存器设置为0x07C0，引导代码当前所处地址（源地址）
	mov		$INITSEG, %ax
	mov		%ax, %es		# 将es段寄存器设置为0x9000,引导代码要被复制到的目的地址
	mov		$256, %cx		# movsw 一次移动1个字，总共移动次数为 512字节/2 = 256个字，循环256次
	sub		%si, %si		# 源地址偏移si清零，ds:si = 0x07C0:0x0000，ds:si物理地址0x07c00
	sub		%di, %di		# 目标地址di清零， es:si = 0x9000:0x0000，es:di物理地址0x90000
	rep						# 循环指令，重复执行并递减cx的值，到cx==0时停止
	movsw					# 将ds:si复制到es:di，每次搬运2字节
	ljmp	$INITSEG, $go	# 段间跳转，跳转到复制后的代码段go标志处，即cs:ip = INITSEG(0x9000):go

# step2. 设置新位置bootsect代码运行的ds，es，ss，sp段寄存器值
# 从现在开始，CPU移动到0x90000位置处的代码中执行。
# 这段代码设置几个寄存器，包括栈寄存器ss和sp。栈指针sp只要指向远大于512字节偏移（即地址0x90200）处都可以。因为
# 从0x90200地址开始出还要开始放置setup程序，而此时setup程序大约为４个扇区，因此sp要指向大于（0x200+0x200*4+堆栈大小）位置处。
# 这里sp设置为0x9ff00-12（参数表长度），即sp=0xfef4。在此之上位置会存放一个自建的驱动器参数表。实际上BIOS把引导扇区加载到0x7c00处
# 并把执行权交给引导程序时，ss=0x00，sp=0xfffe。
go:	mov		%cs, %ax			# 跳转到移动后代码执行的代码段寄存器cs = 0x9000
	mov		%ax, %ds
	mov		%ax, %es
 	#put 	stack at 0x9ff00	# 此指令已不支持
	mov		%ax, %ss
	mov		$0xFF00, %sp		# arbitrary value >>512 # 栈空间的起始地址为0x9ff00(ss:0x9000,sp:0xFF00)

# load the setup-sectors directly after the bootblock.
# Note that 'es'(0x9000) is already set up. 

# step3. 加载setup块，从磁盘中把第2到5个扇区的setup.s程序读入到内存0x90200地址处。
# 注意es已经设置好了.(在移动代码时es已经指向目的段地址处0x9000)

# 以下代码的用途是利用ROM BIOS中断INT 0x13将setup模块从磁盘第2个扇区开始读到0x90200开始处，共读4个扇区。在读操作过程中如果读出错，则显示
# 磁盘上出错扇区位置,然后复位驱动器并重试,没有退路.
# INT 0x13读扇区使用调用参数设置如下:
# ah = 0x02  读磁盘扇区到内存		al = 需要读出的扇区数量;
# ch = 磁道(柱面)号的低8位;		cl = 开始扇区(位0~5),磁道号高2位(位6~7);
# dh = 磁头号；				dl = 驱动器号（如果是硬盘则位7要置位）；
# es:bx 指向数据缓冲区;	如果出错则CF标志置位,ah中是出错码.
load_setup:
	mov		$0x0000, %dx		# drive 0, head 0 # dh=磁头号，dl=驱动器号(硬盘则7要置位)
	mov		$0x0002, %cx		# sector 2, track 0 # ch=磁道(柱面)号的低八位   cl＝开始扇区(位0-5),磁道号高2位(位6－7)
	mov 	$0x0200, %bx		# es:bx = 0x9000:0200，紧接着bootsect 0x9000:0x01FF(1个扇区512B大小)
	mov		$(0x0200+SETUPLEN), %ax	# service 2, nr of sectors # ah=0x02 读磁盘扇区到内存	al＝需要读出的扇区数量
	int		$0x13				# read it # (interupt 19)BIOS中断，es:bx ->指向数据缓冲区；如果出错则CF标志置位，ah保存错误码
	jnc		ok_load_setup		# ok - continue # cf标志寄存器为0(读取成功)就跳转至ok_load_setup
	mov		$0x0000, %dx		# dx:需要复位的驱动器信息
	mov		$0x0000, %ax		# reset the diskette # cf!=０中断出错复位dx指定的驱动器
	int		$0x13				# 0x13中断，ah=0x00 复位驱动器，，ah保存错误码
	jmp		load_setup

# step4. 取磁盘驱动器参数
ok_load_setup:
# Get disk drive parameters, specifically nr of sectors/track
# 这段代码取磁盘驱动器的参数,实际上是取每磁道扇区数,并保存在位置sectors处.
# 取磁盘驱动器参数INT 0x13调用格式和返回信息如下:
# ah = 0x08	dl = 驱动器号(如果是硬盘则要置位7为1).
# 返回信息:
# 如果出错则CF置位,并且ah = 状态码.
# ah = 0, al =0 ,	bl = 驱动器类型(AT/PS2)
# ch = 最大磁道号的低8位	cl = 每磁道最大扇区数(位0~5),最大磁道号高2位(位6~7)
# dh = 最大磁头数		dl = 驱动器数量
# es:di 软驱磁盘参数表.
	mov		$0x00, %dl			# floppy # DL＝驱动器，00H~7FH：软盘；80H~0FFH：硬盘
	mov		$0x0800, %ax		# AH=8 is get drive parameters # ah=0x08 读取磁盘参数
	int		$0x13
	#mov 	$0x00, %ch
	#seg 	cs					# 下一条语句的操作数在cs所指段中
	and		$0x003f, %cx		# 获取cx中 0-5 位 = 每磁道最大扇区数
	mov		%cx, %cs:sectors+0	# %cs means sectors is in %cs # 保存每磁道扇区数
	mov		$INITSEG, %ax
	mov		%ax, %es			# 为下面int 10h答应字符设置字符串地址所在段 $INITSEG（0x9000）

# 通过设置显示模式达到清屏效果
	mov 	$0x0003, %ax		# AH = 00H 设定显示模式；AL = 03H 文字模式，分辨率 80*25，颜色 16
	
#通过滚屏达到清屏效果
	#mov	$0x0600, %ax		# AH = 06H 滚动屏幕，AL = 00 清窗口		
	#mov	$0x0000, %cx 		# CH = 左上角的行号， CL = 左上角的列号
	#mov	$0x184F, %dx 		# DH = 右下角的行号， DL = 右下角的行号
	#mov	$0x17, %bh			# 属性为蓝底白字
	
	int		$0x10
	
# Print some inane message
# 显示信息:"'Loading'+回车+换行",共显示包括回车和换行控制字符在内的9个字符.
# BIOS中断0x10功能号 ah = 0x03,读光标位置.
# 输入:bh = 页号
# 返回: ch = 扫描开始线; cl = 扫描结束线; dh = 行号(0x00 顶端); dl = 列号(0x00 最左边).
#
# BIOS中断0x10功能号 ah = 0z13,显示字符串.
# 输入: al = 放置光标的方式及规定属性.0x01表示使用bl中的属性值,光标停在字符串结尾处.
# es:bp此寄存器对指向要显示的字符串起始位置处.cx = 显示的字符串字符数.bh = 显示页面号;
# bl = 字符属性. dh = 行号; dl = 列号.
	mov		$0x03, %ah			# read cursor pos # ah=0x03指示读光标位置
	xor		%bh, %bh
	int		$0x10				# dh(row 0-24) dl(col 0-79) # 0x10号中断,读取光标位置，DH = 光标行数，DL = 光标列数

	mov		$32, %cx			# nr of characters # CX = 串长度
	mov		$0x000b, %bx		# page 0, attribute b，attribute 7 (normal) # BH = 页号， BL = 属性
	#lea	msg1, %bp
	mov		$msg1, %bp			# 指向要显示字符串的地址,即显示在屏幕上的第一个string "linux 0.12 OS is booting ..."
	mov		$0x1301, %ax		# write string, move cursor # ah=0x13 输出一个字符，移动一下光标
	int		$0x10				# 实现在屏幕上连续打印字符

# step4. 加载系统内核代码
# ok, we've written the message, now we want to load the system (at 0x10000)
	mov		$SYSSEG, %ax		#
	mov		%ax, %es			# segment of 0x01000 # 内核代码加载段地址 es = 0x1000
	call	read_it				# 读取磁盘上的system模块，读到 es:0x0000 处
	call	kill_motor			# 关闭驱动器

# After that we check which root-device to use. If the device is
# defined (#= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.
# 确定使用哪个根文件系统设备,若指定了设备(开始的ax!=0)，就直接用给定的设备

# 软驱的主设备号是 2，次设备号 = type * 4 + nr
# 其中，type 是软驱的类型（比如 2 表示 1.2MB，7 表示 1.44MB）
# nr 等于 0~3 时分别对应软驱 A、B、C、D
# 因为是可引导的驱动器，所以肯定是 A 驱，所以 nr = 0
# 前文已经说过，设备号 = (主设备号 << 8) + 次设备号
# 对于 1.2MB 的软驱，设备号 = 2 << 8 + 2 * 4 + 0 = 0x208
# 对于1.44MB 的软驱，设备号 = 2 << 8 + 7 * 4 + 0 = 0x21C

	#seg 	cs
	mov		%cs:root_dev+0, %ax # ax = ROOT_DEV（0x301）
	cmp		$0, %ax
	jne		root_defined		# 如果ROOT_DEV不等于0，则跳转到 root_defined
	#seg 	cs
	mov		%cs:sectors+0, %bx	# 取磁道扇区数，如果sectors==15,则说明是1.2Mb驱动器
								# 如果sectors==18,则说明是1.44Mb驱动器
	mov		$0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp		$15, %bx			# 判断磁道扇区数是否为15
	je		root_defined		# 如果等于15，说明是1.2MB的软盘
	mov		$0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp		$18, %bx			# 判断每磁道扇区数是否等于18
	je		root_defined
undef_root:
	jmp 	undef_root			# 如果都不是，死循环
root_defined:
	#seg 	cs
	mov		%ax, %cs:root_dev+0	# 将检查过的设备号保存到 root_dev 中

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:
	ljmp	$SETUPSEG, $0		# 本程序执行完毕，跳转0x9020:0x0000（setup.s程序开始处）去执行

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
# 以下是被调用的块的详细代码,以及显示在屏幕的文字信息的数据

# 磁盘读的顺序：0磁头0磁道1-N扇区 -> 1磁头0磁道1-N扇区 -> 0磁头1磁道1-N扇区 -> 1磁头1磁道1-N扇区
sread:	
	.word	1 + SETUPLEN		# sectors read of current track # 当前磁道已经读取的扇区数（引导扇区1 + setup模块4 = 5）
head:
	.word	0					# current head # 当前磁头号
track:
	.word	0					# current track # 当前磁道号

# 读取磁盘上system模块函数
read_it:
	mov		%es, %ax
	test	$0x0fff, %ax		# 测试es段地址是否在4k边界，最终system模块加载内存地址边界64KB边界(0x1000 << 4 = 0x10000)
die:
	jne		die					# es must be at 64kB boundary # 如果不是则进入死循环
	xor 	%bx, %bx			# bx is starting address within segment # 段内偏移，清零 bx = 0
rp_read:						# 重复读system模块
	mov 	%es, %ax
	cmp		$ENDSEG, %ax		# have we loaded all yet? # ax - ENDSEG，看是否到了末尾，ENDSEG =SYSSEG+SYSSIZE = 0x10000 + 0x30000 = 0x40000，SYSSIZE = 0x3000*0x10 = 192kB
	jb		ok1_read			# ax >= 0x40000则返回
	ret
ok1_read:
	#seg 	cs
	mov		%cs:sectors+0, %ax	# 每磁道总扇区数
	sub		sread, %ax		# ax = ax - sread，得出本磁道未读扇区数
	mov		%ax, %cx
	shl		$9, %cx			# 右移9位，计算剩余扇区的总字节数 总字节数 = 扇区数cx << 9 = 扇区数cx * 512
	add		%bx, %cx		# 偏移地址累加将要读取的字节数 cx = ax * 512 + bx
	jnc 	ok2_read		# 若cx < 0x10000（CF=0,没有进位）则跳转到ok2_read，不会越界
	je 		ok2_read		# 若cx = 0（ZF=1），说明刚好不越界，则跳转到ok2_read
	xor 	%ax, %ax		# 执行到这里说明越界，令 ax = 0x0000
	sub 	%bx, %ax		# 计算bx离边界有多远，用0减去bx，结果在ax中
	shr 	$9, %ax			# 越界后，只读到越界的扇区，读取字节数 = 扇区数ax << 9 = 扇区数 * 512
ok2_read:
	call 	read_track		# 调用read_track过程，用AL传参,读取AL个扇区到ES:BX
						# read_track 中有出错检测，能返回，说明读取成功（AH=0）
	mov 	%ax, %cx		# AL中是返回值，即实际读到的扇区数目，cx是该次操作已经读取的扇区数
	add 	sread, %ax		# ax是当前磁道已经读取的扇区数
	#seg 	cs
	cmp 	%cs:sectors+0, %ax
	jne 	ok3_read		# 如果当前磁道还有扇区未读，跳转到ok3_read
	mov 	$1, %ax			# 说明当前磁道的扇区数已读完
	sub 	head, %ax		# ax = 1 - 磁头号
	jne 	ok4_read		# 不相等说明磁头号为0，跳转到 ok4_read，ax=1,读完0磁头，再读1磁头
	incw    track 			# 说明磁头号为1，ax=0,设置磁头号为0，磁道号增加1
ok4_read:
	mov		%ax, head		# 保存当前磁头号
	xor		%ax, %ax		# ax=0, 当前磁道已读扇区数置0
ok3_read:
	mov		%ax, sread		# 更新当前磁道已经读取的扇区数
	shl		$9, %cx			# cx当前磁道已经读取的扇区数，乘以512得当前磁道已经读取字节数
	add		%cx, %bx		# 更新偏移地址
	jnc		rp_read			# 没有进位则跳转到rp_read继续读
	mov		%es, %ax		# 有进位，说明bx达到了64kB边界
	add		$0x1000, %ax
	mov		%ax, %es		# es增加0x1000
	xor		%bx, %bx		# 偏移地址清零 bx = 0x0
	jmp		rp_read			# 继续读取

read_track:
	push	%ax
	push	%bx
	push	%cx
	push	%dx
	mov		track, %dx		# 当前磁道号
	mov		sread, %cx		# 已经读取的扇区数
	inc		%cx				# CL是起始扇区号
	mov		%dl, %ch		# CH是磁道号
	mov		head, %dx		# 当前磁头号
	mov		%dl, %dh		# DH是磁头号
	mov		$0, %dl			# DL是驱动器号，0表示软盘
	and		$0x0100, %dx	# DH是磁头号，磁头号不大于 1
	mov		$2, %ah			# 功能号2，读扇区
	int		$0x13			# CF=1，表示出错，复位磁盘
	jc		bad_rt
	pop		%dx
	pop		%cx
	pop		%bx
	pop		%ax
	ret

# 读磁盘操作出错.则先显示出错信息,然后执行驱动器复位操作(磁盘中断功能号0),再跳转到read_track处重试.
bad_rt:	
	mov		$0, %ax			# AH=0，磁盘复位功能
	mov		$0, %dx			# DL是驱动器号，0表示软盘
	int		$0x13
	pop		%dx
	pop		%cx
	pop		%bx
	pop		%ax
	jmp		read_track		# 重新读取

#/*
# * This procedure turns off the floppy drive motor, so
# * that we enter the kernel in a known state, and
# * don't have to worry about it later.
# * 这个子程序用于关闭软驱的马达,这样我们进入内核后就能知道它所处的状态,以后就无须担心它了.
# */
kill_motor:
	push	%dx
	mov		$0x3f2, %dx		# 软盘控制器的端口-数字输出寄存器端口，只写
	mov		$0, %al			# 驱动器A，关闭FDC，禁止DMA和中断请求，关闭马达
	outsb					# 将al的值写入端口dx
	pop		%dx
	ret

sectors:
	.word	0

msg1:
	.byte 	13,10
	.ascii	"linux 0.12 OS is booting ..."
	.byte	13,10

	# 此bootsect.s只适用于软盘，硬盘存在分区表，引导程序只能占用引导分区446 bytes，硬盘分区表DPT需要占用64 bytes，每个表项16bytes
	# 表示下面语句从地址508(0x1FC)开始,所以root_dev在启动扇区的第508开始的两个字节中.
	
	.org	506
	# .org 伪指令的格式是 .org new_lc, fill
	# 把当前区的位置计数器设置为 new_lc
	# 当位置计数器值増长时，所跳跃过的字节将被填入值 fill
	# 如果省略了逗号和 fill，则填入 0
swap_dev:
	.word 	SWAP_DEV		#第506 byte，存放交换分区文件系统所在设备号（init/main.c中会用）
root_dev:
	.word 	ROOT_DEV		#第508 byte，存放根文件系统所在设备号（init/main.c中会用）
# 下面是启动盘且有有效引导扇区的标志.仅供BIOS中的程序加载引导扇区时识别使用.它必须位于引导扇区的最后两个字节中.
boot_flag:
	.word 	0xAA55			#第511,512byte

.text
endtext:
.data
enddata:
.bss
endbss:

# 硬盘分区表说明
# 为了实现多个操作系统共享硬盘资源，硬盘可以在逻辑上分为1--4 个分区。每个分区之间的扇区号
# 是邻接的。分区表由4 个表项组成，每个表项由16 字节组成，对应一个分区的信息，存放有分区的大小
# 和起止的柱面号、磁道号和扇区号，见下表所示。分区表存放在硬盘的0柱面0头第1个扇区的0x1BE--0x1FD处。

# 硬盘分区表结构
# 位置 		名称 		大小 	说明
# 0x00 		boot_ind 	字节 	引导标志。4个分区中同时只能有一个分区是可引导的。（0x00-不从该分区引导操作系统；0x80-从该分区引导操作系统）
# 0x01 		head 		字节 	分区起始磁头号。
# 0x02 		sector 		字节 	分区起始扇区号(位0-5)和起始柱面号高2 位(位6-7)。
# 0x03 		cyl 		字节 	分区起始柱面号低8 位。
# 0x04 		sys_ind 	字节 	分区类型字节。0x0b-DOS; 0x80-Old Minix; 0x83-Linux …
# 0x05 		end_head 	字节 	分区的结束磁头号。
# 0x06 		end_sector 	字节 	结束扇区号(位0-5)和结束柱面号高2 位(位6-7)。
# 0x07 		end_cyl 	字节 	结束柱面号低8 位。
# 0x08--0x0b 	start_sect 	长字 	分区起始物理扇区号。
# 0x0c--0x0f 	nr_sects 	长字 	分区占用的扇区数。
