#ifndef BINDLESS
#define BINDLESS

uint getBinding(uint handle)
{
    return handle & 0xFFFFu;
}

uint getIndex(uint handle)
{
    return (handle >> 16) & 0xFFFFu;
}

#endif
