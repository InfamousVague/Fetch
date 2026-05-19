#ifndef CFETCH_ENGINE_H
#define CFETCH_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Flat C status row mirrored into Swift's TorrentStatus. */
typedef struct {
    char id[48];          /* v1 info-hash hex (40 chars) */
    char name[320];
    double progress;      /* 0..1 */
    long long down_rate;  /* bytes/sec */
    long long up_rate;
    long long total_bytes;
    long long done_bytes;
    long long uploaded_bytes;
    int peers;
    int seeds;
    int state;            /* 0 queued 1 checking 2 downloading 3 seeding 4 paused 5 error */
} FEStatus;

void *fe_create(const char *save_path);
void  fe_destroy(void *eng);

/* return 0 on success, non-zero on error */
int   fe_add_magnet(void *eng, const char *uri);
int   fe_add_buffer(void *eng, const unsigned char *buf, long len);

void  fe_set_save_path(void *eng, const char *path);
void  fe_pause(void *eng, const char *id);
void  fe_resume(void *eng, const char *id);
void  fe_remove(void *eng, const char *id, int delete_data);

/* fill up to `max` rows, return count written */
int   fe_poll(void *eng, FEStatus *out, int max);

#ifdef __cplusplus
}
#endif

#endif /* CFETCH_ENGINE_H */
