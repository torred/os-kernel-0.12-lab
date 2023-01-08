/* 定义了设置或修改描述符/中断门等的嵌入式汇编宏 */

/* 切换用户运行模式, 利用iret指令实现从内核模式切换到用户模式去执行初始任务0 */
/*=========
 * 0x17
 * esp
 * eflags
 * 0x0f
 * 0x1    <- esp
 *=========
 * iret
 * 依次弹出栈到: eip -> cs -> eflag -> esp -> ss
*/
#define move_to_user_mode()             \
__asm__ (                               \
    "movl %%esp, %%eax\n\t"             /* 保存堆栈指针esp到eax寄存器中,esp是当前栈顶，就是那个大小为1个页的user_stack的那个栈. */\
    "pushl $0x17\n\t"                   /* 首先将堆栈段选择符(SS)入栈, 段选择子,0x17=0b0001 0111,即RPL=3,TI=1选择LDT,10=2表示LDT的第三项 */\
    "pushl %%eax\n\t"                   /* 然后将保存的堆栈指针值(esp)入栈 */\
    "pushfl\n\t"                        /* 将标志寄存器(eflags)内容入栈 */\
    "pushl $0x0f\n\t"                   /* 将Task0代码段选择符(cs)入栈,cs选择子, 0x0f=0b0000 1111,RPL=3用户态,TI=1选择LDT,1表示LDT的第二项. */\
    "pushl $1f\n\t"                     /* 将下面标号1的偏移地址(eip)入栈. */\
    "iret\n"                            /* 执行iret隐含依次弹出eip,cs,eflag,esp,ss,弹出eip则会跳转到1处. */\
    "1:\tmovl $0x17, %%eax\n\t"         /* 此时开始执行任务0 */\
    "mov %%ax, %%ds\n\t"                /* 初始化段寄存器指向本局部表数据段,此时ds指向内核数据段 */\
    "mov %%ax, %%es\n\t"                /* 初始化段寄存器指向本局部表数据段,此时es指向内核数据段 */\
    "mov %%ax, %%fs\n\t"                /* 初始化段寄存器指向本局部表数据段,此时fs指向内核数据段 */\
    "mov %%ax, %%gs"                    /* 初始化段寄存器指向本局部表数据段,此时gs指向内核数据段 */\
    :::"ax")

#define sti() __asm__ ("sti"::)         /* 开中断 */
#define cli() __asm__ ("cli"::)         /* 关中断 */
#define nop() __asm__ ("nop"::)         /* 空操作 */

#define iret() __asm__ ("iret"::)       /* 中断返回 */

/**
 * 设置门描述符宏，根据参数中的中断或异常过程地址addr,门描述符类型type和特权级信息dpl,设置位于地址gate_addr处的门描述符.
 * (注意:下面"偏移"值是相对于内核代码或数据段来说的).
 * @param[in]   gate_addr   在中断描述符表中的偏移量
 * @param[in]   type        门描述符类型
 * @param[in]   dpl         特权级信息
 * @param[in]   addr        中断或异常过程函数地址
 * %0 - (由dpl,type组合成的类型标志字); %1 - (描述符低4字节地址);
 * %2 - (描述符高4字节地址); %3 - edx(程序偏移地址addr); %4 - eax(内核代码段选择符0x8).
 */
#define _set_gate(gate_addr, type, dpl, addr)               \
    __asm__ ("movw %%dx,%%ax\n\t"                           /* 将addr低字存入ax, 与选择子0x8组合成描述符低4字节 */\
            "movw %0,%%dx\n\t"                              /* 将类型标志字存入dx, 与偏移高字组合成描述符高4字节 */\
            "movl %%eax,%1\n\t"                             /* 分别设置门描述符的低4字节(eax)和高4字节(edx) */\
            "movl %%edx,%2"                                 \
            :                                               \
            : "i" ((short) (0x8000+(dpl<<13)+(type<<8))),   /* 高字的低字节，P(1)&DPL&S(0)*Type */\
            "o" (*((char *) (gate_addr))),                  \
            "o" (*(4+(char *) (gate_addr))),                \
            "d" ((char *) (addr)),"a" (0x00080000))         /* edx为中断或异常函数addr, eax为段选择子为8 */

/**
 * 设置中断门函数(自动屏蔽随后的中断)
 * @param[in]   n       中断号
 * @param[in]   addr    中断程序偏移地址
 * &idt[n]是中断描述表中中断号n对应项的偏移值;中断描述符的类型是14,DPL为0,此中断为特权级中断
 * dh = (addr.hi) (0x8000 + (0x0 << 13) + 0xe << 8 = 0x8e00)
 * dl = (selector = 0x0008) (addr.lo)
 */
#define set_intr_gate(n, addr)      _set_gate(&idt[n], 14, 0, addr)

/**
 * 设置陷阱门函数
 * @param[in]   n       中断号
 * param[in]    addr    中断程序偏移地址
 * &idt[n]是中断描述符表中中断号n对应项的偏移值;中断描述符的类型是15,DPL为0,此中断为特权级中断
 * 0x8000 + (0x0 << 13) + 0xf << 8 = 0x8f00
 */
#define set_trap_gate(n, addr)      _set_gate(&idt[n], 15, 0, addr)

/**
 * 设置系统门函数
 * DPL是3,此为用户级中断,因此set_system_gate()设置的中断处理过程能够被所有程序执行
 * 例如单步调试,溢出出错和边界超出出错处理.
 * @param[in]   n       中断号
 * @param[in]   addr    中断程序偏移直
 * &idt[n]是中断描述符表中中断号n对应项的偏移值;中断描述符的类型是15,特权级是3.
 */
#define set_system_gate(n, addr)    _set_gate(&idt[n], 15, 3, addr)

/**
 * 设置段描述符函数(内核中没有用到)
 * @param[in]   gate_addr   描述符地址
 * @param[in]   type        描述符中类型域值
 * @param[in]   dpl         描述符特权值
 * @param[in]   base        段的基地址
 * @param[in]   limit       段限长
 *
 * G->0, D/B->1,L->0,AVL->0,P->1,S->0
 */
#define _set_seg_desc(gate_addr, type, dpl, base, limit) {          \
    *((gate_addr) + 1) = ((base) & 0xff000000) |                    \
        (((base) & 0x00ff0000)>>16) |                               \
        ((limit) & 0xf0000) |                                       \
        ((dpl)<<13) |                                               \
        (0x00408000) |                                              \
        ((type)<<8);                                                \
    *(gate_addr) = (((base) & 0x0000ffff)<<16) |                    \
        ((limit) & 0x0ffff); }


/**
 * 在全局表中设置任务状态段/局部表描述符的地址，通过gdt可以查到状态段和局部描述符表的位置。
 * 状态段局部表段的长度均被设置成104字节。
 * @param[in]   n       在全局表中描述符项n所对应的地址
 * @param[in]   addr    状态段/局部表所在内存的基地址
 * @param[in]   type    描述符中的标志类型字节
 * %0 - eax(地址addr)；%1 - (描述符项n的地址); %2 - (描述符项n的地址偏移2处)；
 * %3 - (描述符项n的地址偏移4处); %4 - (描述符项n的地址偏移5处);%5 - (描述符项n的地址偏移6处);%6 - (描述符项n的地址偏移7处);
 *
 * ldt/tss desc dh:   高16位: 高字节: ldt/tss add 24~31(24~31) - *(n+7)
 *                           低字节: 高4位:0x0, G->0 limit以字节为单位, D/B->0 16位模式,L->0,AVL->0 - *(n+6)
 *                                  低4位:0x0(limit 16~19) - *(n+6)
 *                    低16位: 高字节: 高4位:0x8, P->1 段存在, DPL->00 特权级, S->0 系统描述符 - *(n+5)
 *                                  低4位: ldt: 0x2, X->0,E->0,W->1,A->0 数据段可写,向上扩展 - *(n+5)
 *                                        tss: 0x9, X->1,C->0,R->0,A->1 代码段只执行 - *(n+5)
 *                           低字节: ldt/tss addr 16~23(base:16~23) - *(n+4)
 *  ldt/tss desc dl:  高16位: tss/ldt addr 0~15(base:0~15) - *(n+2)
 *                    低16位: 0x0068(limit:0~15) - *(n)
 */
#define _set_tssldt_desc(n, addr, type) \
__asm__ (\
    "movw $104,%1\n\t"                  /* 将TSS(或LDT)描述符的limit(104)的0-15位存入第0-1字节 */\
    "movw %%ax,%2\n\t"                  /* eax中的addr作为描述符的基址, 基址的0-15位存入第2-3字节 */\
    "rorl $16,%%eax\n\t"                /* eax中的addr基址向右循环16位，高字移到ax中 */\
    "movb %%al, %3\n\t"                 /* eax中的addr基址高字中的低字节al存入第4字节 */\
    "movb $" type ",%4\n\t"             /* 将标志类型字节存入描述符第5字节 */\
    "movb $0x00, %5\n\t"                /* 将TSS(或LDT)描述符的limit域的16-19位&g&d/b&L&avl存入第6字节 */\
    "movb %%ah, %6\n\t"                 /* 将addr基址高字中的高字节ah存入第7字节 */\
    "rorl $16, %%eax"                   /* eax中的addr再右循环16比特,eax恢复原值. */\
    ::"a" (addr), "m" (*(n)), "m" (*(n + 2)), "m" (*(n + 4)), \
     "m" (*(n + 5)), "m" (*(n + 6)), "m" (*(n + 7)) \
    )

/**
 * 在全局表中设置任务状态段描述符(任务状态段描述符的类型是0x89->0b1000 1001)
 * @param[in]   n       该描述符的指针
 * @param[in]   addr    描述符项中段的基地址值
 */
#define set_tss_desc(n,addr)    _set_tssldt_desc(((char *) (n)),addr, "0x89")

/**
 * 在全局表中设置局部表描述符(局部表段描述符的类型是0x82->0b1000 0010)
 * @param[in]   n       该描述符的指针
 * @param[in]   addr    描述符项中段的基地址值
 */
#define set_ldt_desc(n, addr)   _set_tssldt_desc(((char *) (n)),addr, "0x82")
