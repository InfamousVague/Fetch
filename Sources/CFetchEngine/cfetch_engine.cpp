#include "cfetch_engine.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/info_hash.hpp>
#include <libtorrent/span.hpp>
#include <libtorrent/error_code.hpp>

#include <string>
#include <vector>
#include <sstream>
#include <cstring>

namespace lt = libtorrent;

struct Engine {
    lt::session ses;
    std::string save;

    explicit Engine(lt::session_params sp, std::string s)
        : ses(std::move(sp)), save(std::move(s)) {}
};

static std::string hash_hex(lt::torrent_status const& st) {
    std::ostringstream ss;
    if (st.info_hashes.has_v1())      ss << st.info_hashes.v1;
    else if (st.info_hashes.has_v2()) ss << st.info_hashes.v2;
    return ss.str();
}

static lt::torrent_handle find(Engine* e, const char* id) {
    if (!id) return {};
    std::string want(id);
    for (auto& h : e->ses.get_torrents()) {
        if (!h.is_valid()) continue;
        if (hash_hex(h.status()) == want) return h;
    }
    return {};
}

extern "C" {

void* fe_create(const char* save_path) {
    try {
        lt::settings_pack p;
        p.set_int(lt::settings_pack::alert_mask,
                  lt::alert_category::error | lt::alert_category::status);
        p.set_bool(lt::settings_pack::enable_dht, true);
        p.set_bool(lt::settings_pack::enable_lsd, true);
        p.set_bool(lt::settings_pack::enable_upnp, true);
        p.set_bool(lt::settings_pack::enable_natpmp, true);
        p.set_str(lt::settings_pack::user_agent, "Fetch/0.1 libtorrent");
        p.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:6881,[::]:6881");
        lt::session_params sp(p);
        return new Engine(std::move(sp), save_path ? save_path : ".");
    } catch (...) {
        return nullptr;
    }
}

void fe_destroy(void* eng) {
    delete static_cast<Engine*>(eng);
}

int fe_add_magnet(void* eng, const char* uri) {
    auto* e = static_cast<Engine*>(eng);
    if (!e || !uri) return 1;
    try {
        lt::error_code ec;
        lt::add_torrent_params atp = lt::parse_magnet_uri(uri, ec);
        if (ec) return 2;
        atp.save_path = e->save;
        e->ses.add_torrent(std::move(atp), ec);
        return ec ? 3 : 0;
    } catch (...) { return 9; }
}

int fe_add_buffer(void* eng, const unsigned char* buf, long len) {
    auto* e = static_cast<Engine*>(eng);
    if (!e || !buf || len <= 0) return 1;
    try {
        lt::span<char const> span(reinterpret_cast<char const*>(buf),
                                  static_cast<std::ptrdiff_t>(len));
        lt::add_torrent_params atp = lt::load_torrent_buffer(span);
        atp.save_path = e->save;
        lt::error_code ec;
        e->ses.add_torrent(std::move(atp), ec);
        return ec ? 3 : 0;
    } catch (...) { return 9; }
}

void fe_set_save_path(void* eng, const char* path) {
    auto* e = static_cast<Engine*>(eng);
    if (e && path) e->save = path;
}

void fe_pause(void* eng, const char* id) {
    auto h = find(static_cast<Engine*>(eng), id);
    if (h.is_valid()) {
        h.unset_flags(lt::torrent_flags::auto_managed);
        h.pause();
    }
}

void fe_resume(void* eng, const char* id) {
    auto h = find(static_cast<Engine*>(eng), id);
    if (h.is_valid()) h.resume();
}

void fe_remove(void* eng, const char* id, int delete_data) {
    auto* e = static_cast<Engine*>(eng);
    auto h = find(e, id);
    if (e && h.is_valid()) {
        e->ses.remove_torrent(h, delete_data ? lt::session::delete_files
                                              : lt::remove_flags_t{});
    }
}

int fe_poll(void* eng, FEStatus* out, int max) {
    auto* e = static_cast<Engine*>(eng);
    if (!e || !out || max <= 0) return 0;
    int n = 0;
    try {
        for (auto& h : e->ses.get_torrents()) {
            if (n >= max || !h.is_valid()) continue;
            lt::torrent_status st = h.status();
            FEStatus& r = out[n];
            std::memset(&r, 0, sizeof(r));

            std::string id = hash_hex(st);
            std::strncpy(r.id, id.c_str(), sizeof(r.id) - 1);
            std::string nm = st.name.empty() ? std::string("(fetching metadata…)") : st.name;
            std::strncpy(r.name, nm.c_str(), sizeof(r.name) - 1);

            r.progress       = st.progress;
            r.down_rate      = st.download_rate;
            r.up_rate        = st.upload_rate;
            r.total_bytes    = st.total_wanted;
            r.done_bytes     = st.total_wanted_done;
            r.uploaded_bytes = st.all_time_upload;
            r.peers          = st.num_peers;
            r.seeds          = st.num_seeds;

            bool paused = bool(st.flags & lt::torrent_flags::paused);
            if (paused) {
                r.state = 4;
            } else {
                switch (st.state) {
                    case lt::torrent_status::checking_files:
                    case lt::torrent_status::checking_resume_data:
                        r.state = 1; break;
                    case lt::torrent_status::downloading_metadata:
                    case lt::torrent_status::downloading:
                        r.state = 2; break;
                    case lt::torrent_status::finished:
                    case lt::torrent_status::seeding:
                        r.state = 3; break;
                    default:
                        r.state = 0; break;
                }
            }
            ++n;
        }
    } catch (...) {}
    return n;
}

} // extern "C"
