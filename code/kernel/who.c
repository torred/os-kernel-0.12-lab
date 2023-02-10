
#define __LIBRARY__
#include <unistd.h>
#include <asm/segment.h>
#include <errno.h>

char mem[80]= {0};

int sys_iam(const char* name)
{
    int i=0;
    int j=0;
    while(get_fs_byte(name+i)!='\0')
    {
        i++;
    }

    if(i>=24)
    {
        return -EINVAL;
    }
    else
    {
        printk("strlen(%s) = %d\n",mem,i);
    }

    while((mem[j]=get_fs_byte(name+j))!='\0')
    {
        j++;
    }
    return j;
}


int sys_whoami(char* name,unsigned int size)
{
    int i=0;
    int j=0;
    while (mem[i]!='\0')
    {
        i++;
    }

    if (i>size)
    {
        return -1;
    }

    while(mem[j]!='\0')
    {
        put_fs_byte(mem[j],(name+j));
        j++;
    }
    return j;
}
