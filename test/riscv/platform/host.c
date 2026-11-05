/* Single-context bare-metal host: no OS, TLS, atomics, or compiler-rt library.
 * Its allocator deliberately owns a fixed test heap, as a real platform may. */
typedef __SIZE_TYPE__ usize;
typedef unsigned int u32;
typedef unsigned long long u64;
static unsigned char heap[2097152] __attribute__((aligned(16)));
static usize used;
static unsigned depth;
static void finish(int ok) {
    *(volatile u32 *)0x100000 = ok ? 0x5555 : 0x13333;
    for (;;) {}
}
void roc_acquire_runtime_lock(void) { ++depth; }
void roc_release_runtime_lock(void) { if (!depth) finish(0); --depth; }
void *roc_alloc(usize n, usize a) {
    if (!depth) finish(0);
    if (a < sizeof(usize)) a = sizeof(usize);
    usize pos = (used + sizeof(usize) + a - 1) & ~(a - 1);
    if (pos + n > sizeof(heap)) finish(0);
    ((usize *)(heap + pos))[-1] = n;
    used = pos + n;
    return heap + pos;
}
void roc_dealloc(void *p, usize a) { (void)p; (void)a; if (!depth) finish(0); }
void *roc_realloc(void *p, usize n, usize a) {
    unsigned char *q = roc_alloc(n, a);
    usize old = ((usize *)p)[-1];
    for (usize i = 0; i < n && i < old; ++i) q[i] = ((unsigned char *)p)[i];
    return q;
}
static void write_bytes(const unsigned char *p, usize n) {
    for (usize i = 0; i < n; ++i) *(volatile unsigned char *)0x10000000 = p[i];
}
void roc_dbg(const unsigned char *p, usize n) { write_bytes(p, n); }
void roc_expect_failed(const unsigned char *p, usize n) { write_bytes(p, n); finish(0); }
void roc_crashed(const unsigned char *p, usize n) { write_bytes(p, n); finish(0); }
typedef struct { usize words[3]; } RocStr;
void roc_uart_write(RocStr s) {
    const unsigned char *b = (const unsigned char *)&s;
    if (!depth) finish(0);
    if (b[sizeof(s)-1] & 128) write_bytes(b, b[sizeof(s)-1] & 127);
    else write_bytes((const unsigned char *)s.words[0], s.words[2]);
}
typedef struct { double x, y; } Pair;
typedef struct { float f; int i; } Mixed;
Pair roc_host_pair(Pair value) { if (!depth) finish(0); return value; }
Mixed roc_host_mixed(Mixed value) { if (!depth) finish(0); return value; }
extern void roc_main(void);
extern float roc_f32(float);
extern double roc_f64(double);
extern Pair roc_pair(Pair);
extern Mixed roc_mixed(Mixed);
extern Mixed roc_overflow(float,float,float,float,float,float,float,float,float,Mixed);
static u32 float_bits(float f) { union { float f; u32 u; } v = { .f = f }; return v.u; }
static u64 double_bits(double f) { union { double f; u64 u; } v = { .f = f }; return v.u; }
void firmware_main(void) {
    if (float_bits(roc_f32(1.25f)) != 0x3fa00000) finish(0);
    if (double_bits(roc_f64(2.5)) != 0x4004000000000000ULL) finish(0);
    Pair pair = roc_pair((Pair){1.25, 2.5});
    if (double_bits(pair.x) != 0x3ff4000000000000ULL || double_bits(pair.y) != 0x4004000000000000ULL) finish(0);
    Mixed mixed = roc_mixed((Mixed){1.25f, 7});
    if (float_bits(mixed.f) != 0x3fa00000 || mixed.i != 7) finish(0);
    mixed = roc_overflow(1,2,3,4,5,6,7,8,9,(Mixed){1.25f, 7});
    if (float_bits(mixed.f) != 0x3fa00000 || mixed.i != 7) finish(0);
    roc_main();
    finish(depth == 0);
}
/* Platform-owned C code provides its own memory primitives. Roc's compiler
 * support must remain private and may not satisfy these references. */
void *memcpy(void *d, const void *s, usize n) { for (usize i=0;i<n;++i) ((unsigned char*)d)[i]=((const unsigned char*)s)[i]; return d; }
void *memset(void *d, int c, usize n) { for (usize i=0;i<n;++i) ((unsigned char*)d)[i]=c; return d; }
