/* Skill Pre-Allocation native module: files, the game's folder and command line.
 * Windows for the game; POSIX for the offline tests (the game's folder and command line then come from
 * the request or the environment). */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#endif
#include <stdlib.h>
#include <string.h>

#include "spa_native.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

struct pf_file {
	HANDLE h;
	uint64_t size;
};

static WCHAR *to_wide(const char *utf8)
{
	int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
	WCHAR *w;

	if (n <= 0)
		return NULL;
	w = (WCHAR *)malloc((size_t)n * sizeof *w);
	if (w && MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, n) <= 0) {
		free(w);
		w = NULL;
	}
	return w;
}

static char *to_utf8(const WCHAR *w, int units)
{
	int n = WideCharToMultiByte(CP_UTF8, 0, w, units, NULL, 0, NULL, NULL);
	char *s;

	if (n < 0)
		return NULL;
	s = (char *)malloc((size_t)n + 1);
	if (!s)
		return NULL;
	if (n)
		WideCharToMultiByte(CP_UTF8, 0, w, units, s, n, NULL, NULL);
	s[n] = '\0';
	if (units < 0 && n > 0)                 /* (the count included the terminating zero) */
		s[n - 1] = '\0';
	return s;
}

pf_file *pf_open(const char *path)
{
	WCHAR *w = to_wide(path);
	HANDLE h;
	LARGE_INTEGER size;
	pf_file *f;

	if (!w)
		return NULL;
	h = CreateFileW(w, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
		FILE_ATTRIBUTE_NORMAL, NULL);
	free(w);
	if (h == INVALID_HANDLE_VALUE)
		return NULL;
	if (!GetFileSizeEx(h, &size) || !(f = (pf_file *)malloc(sizeof *f))) {
		CloseHandle(h);
		return NULL;
	}
	f->h = h;
	f->size = (uint64_t)size.QuadPart;
	return f;
}

int pf_read_at(pf_file *f, uint64_t offset, void *buf, size_t n)
{
	LARGE_INTEGER at;
	char *p = (char *)buf;

	if (offset > f->size || n > f->size - offset)
		return 0;
	at.QuadPart = (LONGLONG)offset;
	if (!SetFilePointerEx(f->h, at, NULL, FILE_BEGIN))
		return 0;
	while (n > 0) {
		DWORD want = n > 0x40000000 ? 0x40000000 : (DWORD)n, got = 0;
		if (!ReadFile(f->h, p, want, &got, NULL) || got == 0)
			return 0;
		p += got;
		n -= got;
	}
	return 1;
}

uint64_t pf_size(const pf_file *f)
{
	return f->size;
}

void pf_close(pf_file *f)
{
	if (f) {
		CloseHandle(f->h);
		free(f);
	}
}

int pf_is_file(const char *path)
{
	WCHAR *w = to_wide(path);
	DWORD a;

	if (!w)
		return 0;
	a = GetFileAttributesW(w);
	free(w);
	return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

#define LONG_PATH 32768                 /* (heap buffers: the game's script thread may have a small stack) */

char *pf_exe_dir(void)
{
	WCHAR *buf = (WCHAR *)malloc(LONG_PATH * sizeof *buf);
	DWORD n, i;
	char *out = NULL;

	if (!buf)
		return NULL;
	n = GetModuleFileNameW(NULL, buf, LONG_PATH - 1);
	if (n > 0 && n < LONG_PATH - 1) {
		buf[n] = 0;
		for (i = n; i > 0; i--) {
			if (buf[i - 1] == L'\\' || buf[i - 1] == L'/') {
				buf[i - 1] = 0;
				break;
			}
		}
		out = to_utf8(buf, -1);
	}
	free(buf);
	return out;
}

char *pf_cwd(void)
{
	WCHAR *buf = (WCHAR *)malloc(LONG_PATH * sizeof *buf);
	DWORD n;
	char *out = NULL;

	if (!buf)
		return NULL;
	n = GetCurrentDirectoryW(LONG_PATH - 1, buf);
	if (n > 0 && n < LONG_PATH - 1)
		out = to_utf8(buf, -1);
	free(buf);
	return out;
}

char *pf_command_line(void)
{
	return to_utf8(GetCommandLineW(), -1);
}

int pf_list_files(const char *dir, const char *suffix, slist *out)
{
	char *pattern = pf_join(dir, "*");
	WCHAR *w = pattern ? to_wide(pattern) : NULL;
	WIN32_FIND_DATAW found;
	HANDLE h;

	free(pattern);
	if (!w)
		return 0;
	h = FindFirstFileW(w, &found);
	free(w);
	if (h == INVALID_HANDLE_VALUE)
		return 0;
	do {
		if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
			char *name = to_utf8(found.cFileName, -1);
			if (name && spa_ends_with_i(name, suffix))
				sl_add(out, name);
			free(name);
		}
	} while (FindNextFileW(h, &found));
	FindClose(h);
	return 1;
}

#else /* POSIX: offline tests */
#include <dirent.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

struct pf_file {
	FILE *fp;
	uint64_t size;
};

pf_file *pf_open(const char *path)
{
	FILE *fp = fopen(path, "rb");
	pf_file *f;

	if (!fp)
		return NULL;
	f = (pf_file *)malloc(sizeof *f);
	if (!f) {
		fclose(fp);
		return NULL;
	}
	fseeko(fp, 0, SEEK_END);
	f->size = (uint64_t)ftello(fp);
	f->fp = fp;
	return f;
}

int pf_read_at(pf_file *f, uint64_t offset, void *buf, size_t n)
{
	if (offset > f->size || n > f->size - offset)
		return 0;
	if (fseeko(f->fp, (off_t)offset, SEEK_SET) != 0)
		return 0;
	return fread(buf, 1, n, f->fp) == n;
}

uint64_t pf_size(const pf_file *f)
{
	return f->size;
}

void pf_close(pf_file *f)
{
	if (f) {
		fclose(f->fp);
		free(f);
	}
}

int pf_is_file(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

char *pf_cwd(void)
{
	char buf[4096];

	return getcwd(buf, sizeof buf) ? spa_strdup(buf) : NULL;
}

char *pf_exe_dir(void)
{
	const char *dir = getenv("SPA_GAME_DIR");

	return dir ? spa_strdup(dir) : pf_cwd();
}

char *pf_command_line(void)
{
	const char *cmd = getenv("SPA_COMMAND_LINE");

	return spa_strdup(cmd ? cmd : "");
}

int pf_list_files(const char *dir, const char *suffix, slist *out)
{
	DIR *d = opendir(dir);
	struct dirent *e;

	if (!d)
		return 0;
	while ((e = readdir(d)) != NULL) {
		char *full = pf_join(dir, e->d_name);
		if (full && pf_is_file(full) && spa_ends_with_i(e->d_name, suffix))
			sl_add(out, e->d_name);
		free(full);
	}
	closedir(d);
	return 1;
}

#endif

int pf_is_absolute(const char *path)
{
	if (!path || !path[0])
		return 0;
	if (path[0] == '/' || path[0] == '\\')
		return 1;
	return ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':';
}

char *pf_join(const char *dir, const char *name)
{
	size_t n = strlen(dir), m = strlen(name);
	char *p = (char *)malloc(n + m + 2);

	if (!p)
		return NULL;
	memcpy(p, dir, n);
	if (n && dir[n - 1] != '/' && dir[n - 1] != '\\') {
#ifdef _WIN32
		p[n++] = '\\';
#else
		p[n++] = '/';
#endif
	}
	memcpy(p + n, name, m + 1);
	return p;
}

/* A small text file (a mod list) as UTF-8: UTF-16 files (with their byte order mark) are converted and
 * a UTF-8 byte order mark is dropped. */
char *pf_read_text(const char *path, size_t max, size_t *len)
{
	pf_file *f = pf_open(path);
	unsigned char *raw;
	size_t n;
	sbuf b;

	if (!f)
		return NULL;
	n = (size_t)pf_size(f);
	if (n > max || !(raw = (unsigned char *)malloc(n + 2))) {
		pf_close(f);
		return NULL;
	}
	if (n && !pf_read_at(f, 0, raw, n)) {
		pf_close(f);
		free(raw);
		return NULL;
	}
	pf_close(f);
	sb_init(&b);
	if (n >= 2 && raw[0] == 0xFF && raw[1] == 0xFE)
		spa_utf16_to_utf8(&b, raw + 2, (n - 2) / 2);
	else if (n >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF)
		sb_add(&b, raw + 3, n - 3);
	else
		sb_add(&b, raw, n);
	free(raw);
	if (len)
		*len = b.n;
	return sb_take(&b);
}
