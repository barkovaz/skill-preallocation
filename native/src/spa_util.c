/* Skill Pre-Allocation native module: buffers, string lists and text helpers. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "spa_native.h"

/* ---------------------------------------------------------------- byte buffers */
void sb_init(sbuf *b)
{
	b->p = NULL;
	b->n = b->cap = 0;
	b->failed = 0;
}

void sb_free(sbuf *b)
{
	free(b->p);
	sb_init(b);
}

static int sb_reserve(sbuf *b, size_t extra)
{
	size_t want;
	char *p;

	if (b->failed)
		return 0;
	if (b->n + extra + 1 <= b->cap)
		return 1;
	want = b->cap ? b->cap : 64;
	while (want < b->n + extra + 1) {
		if (want > ((size_t)1 << 40)) {
			b->failed = 1;
			return 0;
		}
		want *= 2;
	}
	p = (char *)realloc(b->p, want);
	if (!p) {
		b->failed = 1;
		return 0;
	}
	b->p = p;
	b->cap = want;
	return 1;
}

int sb_add(sbuf *b, const void *data, size_t n)
{
	if (!sb_reserve(b, n))
		return 0;
	if (n)
		memcpy(b->p + b->n, data, n);
	b->n += n;
	b->p[b->n] = '\0';
	return 1;
}

int sb_addc(sbuf *b, char c)
{
	return sb_add(b, &c, 1);
}

int sb_adds(sbuf *b, const char *s)
{
	return sb_add(b, s, strlen(s));
}

int sb_addf(sbuf *b, const char *fmt, ...)
{
	char small[512];
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vsnprintf(small, sizeof small, fmt, ap);
	va_end(ap);
	if (n < 0)
		return 0;
	if ((size_t)n < sizeof small)
		return sb_add(b, small, (size_t)n);
	if (!sb_reserve(b, (size_t)n))
		return 0;
	va_start(ap, fmt);
	vsnprintf(b->p + b->n, (size_t)n + 1, fmt, ap);
	va_end(ap);
	b->n += (size_t)n;
	return 1;
}

char *sb_take(sbuf *b)
{
	char *p;

	if (b->failed)
		return NULL;
	if (!b->p)
		return spa_strdup("");
	p = b->p;
	sb_init(b);
	return p;
}

/* ---------------------------------------------------------------- string lists */
void sl_free(slist *l)
{
	int i;

	for (i = 0; i < l->n; i++)
		free(l->v[i]);
	free(l->v);
	l->v = NULL;
	l->n = l->cap = 0;
}

int sl_add(slist *l, const char *s)
{
	char *copy;

	if (l->n == l->cap) {
		int cap = l->cap ? l->cap * 2 : 8;
		char **v = (char **)realloc(l->v, (size_t)cap * sizeof *v);
		if (!v)
			return 0;
		l->v = v;
		l->cap = cap;
	}
	copy = spa_strdup(s);
	if (!copy)
		return 0;
	l->v[l->n++] = copy;
	return 1;
}

int sl_addf(slist *l, const char *fmt, ...)
{
	char text[1024];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(text, sizeof text, fmt, ap);
	va_end(ap);
	return sl_add(l, text);
}

/* ---------------------------------------------------------------- text */
char *spa_strndup(const char *s, size_t n)
{
	char *p = (char *)malloc(n + 1);

	if (!p)
		return NULL;
	memcpy(p, s, n);
	p[n] = '\0';
	return p;
}

char *spa_strdup(const char *s)
{
	return spa_strndup(s, strlen(s));
}

static int lower(int c)
{
	return (c >= 'A' && c <= 'Z') ? c - 'A' + 'a' : c;
}

int spa_stricmp(const char *a, const char *b)
{
	for (;; a++, b++) {
		int ca = lower((unsigned char)*a), cb = lower((unsigned char)*b);
		if (ca != cb || !ca)
			return ca - cb;
	}
}

int spa_ends_with_i(const char *s, const char *suffix)
{
	size_t n = strlen(s), m = strlen(suffix);

	return n >= m && spa_stricmp(s + n - m, suffix) == 0;
}

const char *spa_basename(const char *path)
{
	const char *base = path;

	for (; *path; path++) {
		if (*path == '/' || *path == '\\')
			base = path + 1;
	}
	return base;
}

/* The order the game reads a table's files in: by the bytes of their names. A file whose name sorts first
 * wins a key both files have, so "!!_my_mod" beats the game's "data__" - and so do names with a capital
 * first letter ("SFO_vanilla"): capitals come before small letters. Mods count on that: SFO's changes to
 * the game's own skills, nodes and set items are in files named SFO_..., Less Lethal Autoresolve's two
 * campaign variables in Less_Lethal_Autoresolve_Table, Free Cult Demolish's building levels in
 * Lan_WH3_FreeCultDemolish_B; files that hold only changes to the game's rows, which would do nothing if
 * they were read after data__. (The modding wiki's list, ! # $ % & ' ( ) + , - ; = @ 0-9 a-z [ ] ^ _ ` { } ~,
 * read as case-insensitive, put them after it.) */
int spa_game_name_cmp(const char *a, const char *b)
{
	const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;

	while (*x && *x == *y) {
		x++;
		y++;
	}
	return (int)*x - (int)*y;
}

uint64_t spa_fnv(uint64_t h, const void *data, size_t n)
{
	const unsigned char *p = (const unsigned char *)data;
	size_t i;

	for (i = 0; i < n; i++) {
		h ^= p[i];
		h *= 0x100000001b3ULL;
	}
	return h;
}

int spa_utf16_to_utf8(sbuf *b, const unsigned char *src, size_t units)
{
	size_t i;

	for (i = 0; i < units; i++) {
		unsigned c = (unsigned)src[2 * i] | ((unsigned)src[2 * i + 1] << 8);
		unsigned char out[4];
		size_t n;

		if (c >= 0xD800 && c <= 0xDBFF && i + 1 < units) {
			unsigned d = (unsigned)src[2 * i + 2] | ((unsigned)src[2 * i + 3] << 8);
			if (d >= 0xDC00 && d <= 0xDFFF) {
				c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
				i++;
			}
		}
		if (c < 0x80) {
			out[0] = (unsigned char)c;
			n = 1;
		} else if (c < 0x800) {
			out[0] = (unsigned char)(0xC0 | (c >> 6));
			out[1] = (unsigned char)(0x80 | (c & 0x3F));
			n = 2;
		} else if (c < 0x10000) {
			out[0] = (unsigned char)(0xE0 | (c >> 12));
			out[1] = (unsigned char)(0x80 | ((c >> 6) & 0x3F));
			out[2] = (unsigned char)(0x80 | (c & 0x3F));
			n = 3;
		} else {
			out[0] = (unsigned char)(0xF0 | (c >> 18));
			out[1] = (unsigned char)(0x80 | ((c >> 12) & 0x3F));
			out[2] = (unsigned char)(0x80 | ((c >> 6) & 0x3F));
			out[3] = (unsigned char)(0x80 | (c & 0x3F));
			n = 4;
		}
		if (!sb_add(b, out, n))
			return 0;
	}
	return 1;
}
