.code16
/*
 * rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
 *
 *	setup.s		(C) 1991 Linus Torvalds
 *
 * setup.s is responsible for getting the system data from the BIOS,
 * and putting them into the appropriate places in system memory.
 * both setup.s and system has been loaded by the bootblock.
 *
 * This code asks the bios for memory/disk/other parameters, and
 * puts them in a "safe" place: 0x90000-0x901FF, ie where the
 * boot-block used to be. It is then up to the protected mode
 * system to read them from there before the area is overwritten
 * for buffer-blocks.
 */
 
# NOTE! These had better be the same as in bootsect.s!

#include <linux/config.h>

.equ	INITSEG, DEF_INITSEG		# we move boot here - out of the way #  存放系统硬件信息的地址 0x9000
.equ	SYSSEG, DEF_SYSSEG		# system loaded at 0x10000 (65536).  # system 存放的地址 0x10000 (65536).
.equ	SETUPSEG, DEF_SETUPSEG		# this is the current segment # setup.s存放的地址 0x9020

.global _start, begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

/*
 * setup.s入口地址
 * 解析BIOS传递过来的参数
 * 设置系统内核运行的局部描述符，中断描述寄存器，全局描述符
 * 设置中断控制芯片，进入保护模式
 * 跳转到system模块中head.s中代码执行
 */
 
	ljmp	$SETUPSEG, $_start	# phaddr: 0x90205
_start:
# step1. 设置段寄存器 ds,es为 0x9020
	mov	%cs,%ax			# 0x9020，也是SETUPSEG
	mov	%ax,%ds			# ds 0x9020
	mov	%ax,%es			# es 0x9020
#
##print some message
#
	mov	$0x03, %ah
	xor	%bh, %bh
	int	$0x10

	mov	$27, %cx
	mov	$0x000b,%bx
	mov	$msg2,%bp		# es:bp = msg2 "Now we are in setup ..."
	mov	$0x1301, %ax
	int	$0x10

## ok, the read went well so we get current cursor position and save it for
## posterity.
## 保存当前光标位置
	mov	$INITSEG, %ax		# this is done in bootsect already, but...
	mov	%ax, %ds		# ds设置成INITSET
	mov	$0x03, %ah	    	# read cursor pos #int 10读光标功能号 3，读取光标位置 
	xor	%bh, %bh
	int	$0x10		    	# save it in known place, con_init fetches #调用中断，读取光标位置，con_init需要使用
	mov	%dx, %ds:0	    	# it from 0x90000. # 光标信息存在dx中，dh = 行，dl = 列，存入0x90000处

## Get memory size (extended mem, kB)
## 获取扩展内存大小
	mov	$INITSEG, %ax
	mov	%ax, %ds
	mov	$0x88, %ah 		# int 15取扩展内存大小功能号0x88
	int	$0x15
	mov	%ax, %ds:2		# save the value of extended memory size in 0x90002,
					# which excludes 1MB. (it's 15MB in this case)
					# 返回从0x100000开始的扩展内存大小信息存入0x90002

## Get video-card data:
## 保存显卡当前显示模式
	mov	$INITSEG, %ax
	mov	%ax, %ds 
	mov	$0x0f, %ah
	int	$0x10
	mov	%bx, %ds:4		# bh = display page (0x00) #存入0x90004
	mov	%ax, %ds:6		# al = video mode, ah = window width (0x50,0x03)  # #存入0x90006
					# 80x25(col*row)

## check for EGA/VGA and some config parameters
## 检查显示方式(EGA/VGA)，并选取参数
	mov	$INITSEG, %ax
	mov	%ax, %ds
	mov	$0x12, %ah		# 0x12功能号，显示器的配置中断
	mov	$0x10, %bl		# 0x10H子功能，读取配置信息
	int	$0x10
	mov	%ax, %ds:8		# 调用中断后ax = 0x1200，把此值存下来不清楚什么用？？，存入0x90008
	mov	%bx, %ds:10		# bh = video mode bl = video memory size(256KB)，存入0x90010
					# bl = VRAM容量（00h = 64K,01h=128H，02h = 192K, 03h = 256K）
					# bh = 0，单色模式；1，彩色模式
	mov	%cx, %ds:12		# EGA 80x25			# 存入0x90012
					# CH = 特征连接器标志位
					# CL = EGA开关设置

	mov	$0x5019, %ax		# 80x25
	mov	%ax, %ds:14		# 存入0x90014

/*
 * 硬盘参数表16字节含义
 * 0x00 字 柱面数
 * 0x02 字节 磁头数
 * 0x03 字 开始减小写电流的柱面(仅PC XT 使用，其它为0)
 * 0x05 字 开始写前预补偿柱面号（乘4）
 * 0x07 字节 最大ECC 猝发长度（仅XT 使用，其它为0）
 * 0x08 字节 控制字节（驱动器步进选择）
 *		位0 未用
 *		位1 保留(0) (关闭IRQ)
 *		位2 允许复位
 *		位3 若磁头数大于8 则置1
 *		位4 未用(0)
 *		位5 若在柱面数+1 处有生产商的坏区图，则置1
 *		位6 禁止ECC 重试
 *		位7 禁止访问重试。
 * 0x09 字节 标准超时值（仅XT 使用，其它为0）
 * 0x0A 字节 格式化超时值（仅XT 使用，其它为0）
 * 0x0B 字节 检测驱动器超时值（仅XT 使用，其它为0）
 * 0x0C 字 磁头着陆(停止)柱面号
 * 0x0E 字节 每磁道扇区数
 * 0x0F 字节 保留。
 */
 
## Get hd0 data(fixed disk parameter table)
## 获取第0个硬盘信息
	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x41, %si		# src #4*0x41是中断向量41在中断向量表中的偏移地址，取中断向量41的值，中断向量0x41保存的是硬盘0参数表的地址
					# lds命令：ds:4*0x46 -> si，ds:4*0x46+2 -> ds，
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0080, %di		# dst: 0x90080 # 传输向量表到达目的地址 es:si -> 9000:0080
	mov	$0x10, %cx		# the size of FDPT is 16) 取16个字节
	rep
	movsb

## Get hd1 data
## 获取第1个磁盘信息
	mov	$0x0000, %ax
	mov	%ax, %ds
	lds	%ds:4*0x46, %si		# 取中断向量46的值，即硬盘1参数表的地址
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di		# 传输向量表到达目的地址 es:di -> 9000:0090
	mov	$0x10, %cx		# 取16个字节
	rep
	movsb

## modify ds # ds修改回0x9000，es为0x9020，为后面显示系统信息做准备
	mov	$INITSEG,%ax
	mov	%ax,%ds
	mov	$SETUPSEG,%ax
	mov	%ax,%es

##show cursor pos #显示当前光标位置
	mov	$0x03, %ah 
	xor	%bh,%bh
	int	$0x10			# 读取光标位置，在光标当前位置处打印
	mov	$11,%cx
	mov	$0x000a,%bx		# 设置显示文字属性
	mov	$cur,%bp
	mov	$0x1301,%ax
	int	$0x10			# 显示光标信息的提示文字
##show detail(row*col)
	mov	%ds:0 ,%ax		# 需要打印的光标位置
	call	print_hex		# 打印16进制数据，ax为输入参数
	call	print_nl

##show memory size # 显示扩展内存大小
	mov	$0x03, %ah
	xor	%bh, %bh
	int	$0x10
	mov	$12, %cx
	mov	$0x000a, %bx
	mov	$mem, %bp
	mov	$0x1301, %ax
	int	$0x10

##show detail(KB)
	mov	%ds:2 , %ax		# 需要打印的内存大小
	call	print_hex

##show nr of cylinders # 显示磁盘磁道数
	mov	$0x03, %ah
	xor	%bh, %bh
	int	$0x10
	mov	$25, %cx
	mov	$0x000a, %bx
	mov	$cyl, %bp
	mov	$0x1301, %ax
	int	$0x10
##show detail
	mov	%ds:0x80, %ax		# 需要打印的第一个硬盘磁道数
	call	print_hex
	call	print_nl

##show nr of heads # 显示磁盘磁头数
	mov	$0x03, %ah
	xor	%bh, %bh
	int	$0x10
	mov	$9, %cx
	mov	$0x000a, %bx
	mov	$head, %bp
	mov	$0x1301, %ax
	int	$0x10
##show detail
	mov	%ds:0x82, %ax		# 需要打印的第一个硬盘磁头数
	call	print_hex
	call	print_nl

##show nr of sectors per track  # 显示每磁道扇区数
	mov	$0x03, %ah
	xor	%bh, %bh
	int	$0x10
	mov	$9, %cx
	mov	$0x000a, %bx
	mov	$sect, %bp
	mov	$0x1301, %ax
	int	$0x10
##show detail
	mov	%ds:0x8e, %ax		# 需要打印的第一个硬盘每磁道扇区数
	call	print_hex
	call	print_nl

## Check that there IS a hd1 :-)
## 检查是否存在第2个硬盘
	mov	$0x01500, %ax
	mov	$0x81, %dl
	int	$0x13
	jc	no_disk1		# cf == 1 表示没有第2个磁盘，跳转到no_disk1
	cmp	$3, %ah			# 判断是否有硬盘
	je	is_disk1
	
## 没有第二个硬盘表则此处参数表清零
no_disk1:
	mov	$INITSEG, %ax
	mov	%ax, %es
	mov	$0x0090, %di
	mov	$0x10, %cx
	mov	$0x00, %ax
	rep
	stosb				# 将累加器AL中的值传递到es:di -> 0x9000:0x0090

is_disk1:
# now we want to move to protected mode ...
# 为开始保护模式做准备
	cli			    	# no interrupts allowed !  # 禁中断

## first we move the system to its rightful place(load kernel module)
## 首先我们将系统模块移动到新的目标位置0x00000000
	mov	$0x0000, %ax
	cld			    	# 'direction'=0, movs moves forward # 指明复制的方向，从低到高
do_move:
	mov	%ax, %es		# destination segment # 此时ax=0x0000，被复制的目的地址es:di -> 0x0000:0000
	add	$0x1000, %ax		# 每次移动0x1000字节(64KB)
	cmp	$0x9000, %ax		# 0x9000 SYS_SIZE 
	jz	end_move
	mov	%ax, %ds		# source segment # 原地址ds:si -> 0x1000:0 0x2000:0 0x3000:0···
	sub	%di, %di		# di = 0，实模式下最大偏移是64k（0x0-0xFFFF，共0x10000h=64kb）,所以一次最多复制这么多
	sub	%si, %si		# 第一次放在0-0x10000处，第二次0x10000-0x20000···
	mov	$0x8000, %cx		# 总共移动了0x8000(32768)字,即0x10000Byte,(65536/1024=64k)
	rep							# 1000:0->000:0,2000:0->1000:0···
	movsw
	jmp	do_move

## then we load the segment descriptors
## setup.s中给出了中断描述表和全局描述符表。在这里把它们的首地址放入指定寄存器中idtr,gdtr中
#  这是专用寄存器
end_move:
	mov	$SETUPSEG, %ax		# right, forgot this at first. didn't work :-)
	mov	%ax, %ds		# 0x9020 # ds指向setup段0x9020
	lidt	idt_48			# load idt with 0,0,0 # 加载中断描述符表寄存器 idt_48: 0x0000, 0x0000, 0x0000, limit = 0 base = 0L
	lgdt	gdt_48			# load gdt with whatever appropriate # 加载全局描述符表寄存器  gdt_48: 0x0009，0x0200+gdt，0x07FF，limit=2048 base = 0x9xxxx,

## that was painless, now we enable A20
## 通过键盘控制器的设置开启A20地址线，准备进入32位寻址模式

/********************************************************
 ** The 3 methods for enabling the A20 Gate are 
	1. Keyboard Controller 
	2. BIOS Function 
	3. System Port


 ** Keyboard Controller: 
	This is the most common method of enabling A20 Gate.The keyboard micro-controller provides functions for disabling and enabling A20.
	Before enabling A20 we need to disable interrupts to prevent our kernel from getting messed up.The port 0x64 is used to send the command byte.

 ** Command Bytes and ports 
	0xDD Enable A20 Address Line 
	0xDF Disable A20 Address Line
	0x64 Port of the 8042 micro-controller for sending commands

 ** Using the keyboard to enable A20:
 ** EnableA20_KB: 
	cli ;Disables interrupts 
	push ax ;Saves AX 
	mov al, 0xdd ;Look at the command list 
	out 0x64, al ;Command Register 
	pop ax ;Restore’s AX 
	sti ;Enables interrupts 
	ret

 ** Using the BIOS functions to enable the A20 Gate: 
 ** The INT 15 2400,2401,2402 are used to disable,enable,return status of the A20 Gate respectively.

 ** Return status of the commands 2400 and 2401(Disabling,Enabling) 
	CF = clear if success 
	AH = 0 
	CF = set on error 
	AH = status (01=keyboard controller is in secure mode, 0x86=function not supported)

 ** Return Status of the command 2402 
	CF = clear if success 
	AH = status (01: keyboard controller is in secure mode; 0x86: function not supported) 
	AL = current state (00: disabled, 01: enabled) 
	CX = set to 0xffff is keyboard controller is no ready in 0xc000 read attempts 
	CF = set on error

 ** Disabling the A20
	push ax 
	mov ax, 0x2400 
	int 0x15 
	pop ax

 ** Enabling the A20 
	push ax 
	mov ax, 0x2401 
	int 0x15 
	pop ax

 ** Checking A20 
	push ax 
	push cx 
	mov ax, 0x2402 
	int 0x15 
	pop cx 
	pop ax

 ** Using System Port 0x92 
 ** This method is quite dangerous because it may cause conflicts with some hardware devices forcing the system to halt.
	Port 0x92 Bits 
	Bit 0 - Setting to 1 causes a fast reset 
	Bit 1 - 0: disable A20, 1: enable A20 
	Bit 2 - Manufacturer defined 
	Bit 3 - power on password bytes. 0: accessible, 1: inaccessible 
	Bits 4-5 - Manufacturer defined 
	Bits 6-7 - 00: HDD activity LED off, 01 or any value is “on”

 ** Code to enable A20 through port 0x92 
	push ax 
	mov al, 2 
	out 0x92, al
	pop ax
********************************************************/

/*
	call	empty_8042		# 8042 is the keyboard controller
	mov	$0xD1, %al		# command write
	out	%al, $0x64
	call	empty_8042
	mov	$0xDF, %al		# A20 on # 开启A20有三种方法，这里是通过键盘控制器开启32位寻址模式
	out	%al, $0x60
	call	empty_8042

# 检查键盘命令队列是否为空，当输入缓冲器为空则可以对其进行写命令
empty_8042:
	.word   0x00eb,0x00eb
    	in      al,#0x64        	; 8042 status port
    	test    al,#2           	; is input buffer full?
    	jnz     empty_8042      	; yes - loop
    	ret
*/
	
# 通过另一种更直接的方式开启A20	
	inb     $0x92, %al			# open A20 line(Fast Gate A20). 
	orb     $0b00000010, %al	# al与00000010或，确保第2位为1，打开A20
	outb    %al, $0x92

/*
 * well, that went ok, I hope. Now we have to reprogram the interrupts :-(
 * we put them right after the intel-reserved hardware interrupts, at
 * int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
 * messed this up with the original PC, and they haven't been able to
 * rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
 * which is used for the internal hardware interrupts as well. We just
 * have to reprogram the 8259's, and it isn't fun.
 */
 
# 设置8259中断控制器
	mov	$0x11, %al		# initialization sequence(ICW1)
					# ICW4 needed(1),CASCADE mode,Level-triggered
	out	%al, $0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2 $表示当前指令地址
	out	%al, $0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb
	
	mov	$0x20, %al		# start of hardware int's (0x20)(ICW2)
	out	%al, $0x21		# from 0x20-0x27
	.word	0x00eb,0x00eb
	
	mov	$0x28, %al		# start of hardware int's 2 (0x28)
	out	%al, $0xA1		# from 0x28-0x2F
	.word	0x00eb,0x00eb		# IR 7654 3210
	
	mov	$0x04, %al		# 8259-1 is master(0000 0100)
	out	%al, $0x21		#
	.word	0x00eb,0x00eb		# INT
	
	mov	$0x02, %al		# 8259-2 is slave(010 --> 2)
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	
	mov	$0x01, %al		# 8086 mode for both
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	
	mov	$0xFF, %al		# mask off all interrupts for now
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1

/*
 * well, that certainly wasn't fun :-(. Hopefully it works, and we don't
 * need no steenking BIOS anyway (except for the initial loading :-).
 * The BIOS-routine wants lots of unnecessary data, and it's less
 * "interesting" anyway. This is how REAL programmers do it.

 * Well, now's the time to actually move into protected mode. To make
 * things as simple as possible, we do no register set-up or anything,
 * we let the gnu-compiled 32-bit programs do that. We just jump to
 * absolute address 0x00000, in 32-bit protected mode.
 */
 
/*
 * cr0
 * 31 30 29 ... 18 17 16 ... 5  4  3  2  1  0
 * PG CD NW     AM    WP     NE ET TS EM MP PE
 */
 
# 开启保护模式
	#mov	$0x0001, %ax		# protected mode (PE) bit # 开启保护模式，此方法已经不用
	#lmsw	%ax			# This is it!
	mov		%cr0, %eax	# get machine status(cr0|MSW)	
	bts	$0, %eax		# turn on the PE-bit 		# cr0的第0位为PE位，置此位为1
	mov	%eax, %cr0		# protection enabled

# 跳转到head.s入口地址startup_32
	.equ	sel_cs0, 0x0008 	# select for code segment 0 (  001:0 :00)  # 0x0008 = 001:0:00(INDEX:TI:RPL)，因此INDEX = 1，TI = 0， RPL = 0
	ljmp	$sel_cs0, $0		# jmp offset 0 of code segment 0 in gdt # 跳转到0x00000000:00000000

# ljmp指令解释：段间跳转，参数1:偏移量，参数2：段选择子
# 跳转到0x0008:0位置，这里的8为保护模式下的段选择子，INDEX = 1，第一个GDT描述符的base = 0x0，offset = 0x0，
# 因此目的地址是0x00000000:0x00000000，物理地址是0x00000000，刚好为head.s的入口

/*
 * 全局描述符表开始处
 * GDT每个表项8字节，具体含义如下：
 *	0x00			00								00					00				0000			0000
 *	base:31..24		G1 D/B1 X1 AVL1 limit:19..16	P1 DPL2 S type4		base:23..16		base:15..0		limit:15..0
 *
 * G：G = 1 段限最小单位4kB，G = 0 段限最小单位1B
 * D/B: type为代码段： D = 1 32位程序，D = 0 16位程序
 *      type为数据段： B = 1 最大访问4GB，D = 0 最大访问64KB
 *      type为堆栈段： B = 1 表示隐含操作(如PUSH/POP)使用ESP为堆栈指针，D = 0 使用SP(隐含操作:未明确定义段属性类型USE16/USE32?66H,67H?) 
 * X: X未使用
 * P: P = 1 该段可用，P = 0 该段不可用
 * DPL: DPL = 0,1,2,3，共4个级别，其中0级别最高，3级别最低
 * S: S = 1 数据段/代码段描述符， S = 0 系统段或或门描述符
 * type: 位0: A(accessed),表明描述符是否已被访问；把选择子装入段寄存器时,该位被标记为1 
 *       位1: 代码段R = 1 可读性代码段，R = 0 不可读代码段；数据段W = 1 表示可写数据段，W = 0 表示只读数据段
 *       位2: 代码段C = 1 表示一致性代码段，C = 0 表示非一致性代码段；数据段E = 1 表示向下扩展的数据段，E = 0 表示非向下扩展的数据段
 *       位3: X = 1 可执行段代码段，X = 0 不可执行数据段
 */

# 此全局描述符表只是临时使用，在head.s中还会重新设置正式全局描画符表
gdt:
	.word	0,0,0,0			# dummy # 第一描述符，作为NULL指向

	# 这里在gdt表中的偏移量为08，联系到我们上面的jmpi 0,8，也就是调用此处的表内容
	# 加载代码段寄存器时，使用这个偏移
	.word	0x07FF			# 8Mb - limit = 2048 (2048 * 4096 = 8Mb)	# limit：0x007FF~0x00000 = 0x800，表示0x800个4kB，0x800*4K = 8MB
	.word	0x0000			# base address=0 # system所在的 0x00000000
	.word	0x9A00			# code read/exec        	# 0x9A = 1001 1010 P = 1 该段可用；DPL = 0级（最高）；type = 1010 可读可执行
	.word	0x00C0			# granularity=4096, 386 	# 0xC0 = 1100 0000 G = 1 段限最小单位4kB；D = 1 32位程序

	# 这里在gdt表中的偏移量是0x10,当加载数据段寄存器时,使用这个偏移
	.word	0x07FF			# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000			# base address=0 # base = 0x00000000
	.word	0x9200			# data read/write			# 0x92 = 1001 0010 P = 1 该段可用；DPL = 0级（最高）；type = 0010 可读可写数据段
	.word	0x00C0			# granularity=4096, 386

/*
 * GDTR/IDTR寄存器值
 * 	0x0000 0000			0000
 * 	base:32..0			limit:15..0
 */
 
idt_48:
	.word	0			# idt limit = 0
	.word	0,0			# idt base = 0L

gdt_48:
	.word	0x7FF			# gdt limit=2048, 256 GDT entries # limit:0x0800~0x0000 每个描述符8字节，总共描述符项 = 0x800 / 8 = 256项
	.word   512+gdt, 0x9	# gdt base = 0X9xxxx  # base = 0x0009 0200+$gdt -> 0x9xxxx，表示从90000开始，偏移bootsect 512字节，再偏移gdt在setup的偏移，得到gdt在内存中的物理地址。
	# 512+gdt is the real gdt after setup is moved to 0x9020 * 0x10

# print_hex()
print_hex:
	mov	$4,%cx
	mov	%ax,%dx

print_digit:
	rol	$4,%dx	    		#循环以使低4位用上，高4位移至低4位
	mov	$0xe0f,%ax  		#ah ＝ 请求的功能值，al = 半个字节的掩码
	and	%dl,%al
	add	$0x30,%al
	cmp	$0x3a,%al
	jl	outp
	add	$0x07,%al

outp:
	int	$0x10
	loop	print_digit
	ret

#打印回车换行
print_nl:
	mov	$0xe0d,%ax
	int	$0x10
	mov	$0xa,%al
	int	$0x10
	ret

msg2:
	.byte	13,10
	.ascii	"Now we are in setup ..."
	.byte	13,10,13,10
cur:
	.ascii	"Cursor POS:"
mem:
	.ascii	"Memory SIZE:"
cyl:
	.ascii	"KB"
	.byte	13,10,13,10
	.ascii	"HD Info"
	.byte	13,10
	.ascii	" Cylinders:"
head:
	.ascii	" Headers:"
sect:
	.ascii	" Secotrs:"
.text
endtext:
.data
enddata:
.bss
endbss:

/*
 * 内存地址	长度	名称			描述
 * 0x90000	2	光标位置			列号(最左边：0x00),行号(最上边:0x00)
 * 0x90002	2	扩展内存参数		系统从1M开始的扩展内存参数
 * 0x90004	2	显示页面			当前显示页面
 * 0x90006	1	显示模式			···
 * 0x90007	2	字符列数			···
 * ···		··					···
 * 0x9000A	1	显示内存			显存大小
 * 0x9000B	1	显示状态			0x00-彩色0x3dx 0x11单色0x3bx
 * 0x9000C	2	显卡特性参数		显存大小
 * ···		···	···				···
 * 0x90080	16	硬盘参数表		第一个硬盘的参数
 * 0x90090	16	硬盘参数表		第二个硬盘的参数(没有的话就是0)
 * 0x901FC	2	根设备号			根文件所在的设备号(bootsect.s中设置的)
 */