#!/usr/bin/env python3
"""pg_http.py -- a table-driven argv model of the HTTP clients permission-guard reads (issue #349, ADR 004).

WHAT IT ANSWERS
    parse(prog, argv) says what an HTTP client call would send: for each request (a curl --next group is one;
    every other client makes one), its method, its URLs, its body as given and as sent, its headers, and whether
    its body or its destination is something the words cannot show. It reads the words only -- no file, no
    environment, no network -- and it never decides a verdict: hooks/permission-guard.sh does that.

WHY TABLES
    PR #348 went through six Codex review rounds, and each round after the security review found one more option
    form the hand-written reader in permission-guard.sh got wrong: attached values, short-option clusters, several
    URLs, --url, --next groups, --expand-*, --request-target/--connect-to/--resolve/Host:, -K, @file and stdin
    bodies, split --json pieces. Here every client's options are listed ONCE, with what each option is for (its
    role) and whether it takes a value, and one reader per option grammar (curl's own, GNU getopt, argparse, clap,
    pflag) walks the words against the table. An option the table does not list is UNKNOWN: it may take the next
    word as its value, and that word may be the URL, so nothing after it is established.

WHERE THE TABLES CAME FROM
    curl    8.7.1    generated from the installed `curl --help all` (258 options); plus the names curl 8.7.1
                     accepts without listing (the positive forms of its --no-* booleans, --ftp-ssl, --ftp-ssl-reqd),
                     each probed against 8.7.1; plus the options curl 8.8 - 8.17 added, from curl's changelog.
    wget    1.24.5   hand-listed from `wget --help` (GNU Wget 1.24.5); wget was not installed where this was built.
    httpie  3.2.4    hand-listed from `http --help` (HTTPie 3.2.4); `http` and `https` are the same program.
    xh      0.24     hand-listed from `xh --help`; `xhs` is xh with https as the default scheme.
    gh api  2.103.3  from the installed `gh api --help`.
    tests/test-pg-http.sh re-reads the installed help of every client it finds and fails when an option this
    file lists disagrees with it about taking a value.

    Listing an option the installed tool lacks is harmless: the tool refuses the whole command, so nothing is
    sent. Reading a value option as a flag is harmless too: its value is then read as one more URL, which can only
    make the call stricter. Reading a FLAG as a value option is the one dangerous mistake -- it hides the next
    word, which may be the URL -- so an option whose arity a source left uncertain is listed as a flag.

ROLES (the third column of a table)
    flag            shapes nothing this module reports (a value option of this role still consumes its value)
    method          the value is the request method
    body:<kind>     the value is a body piece given inline; <kind> says how the client reads it (curl -d reads
                    @file, --data-raw does not, --data-urlencode encodes, --json joins without '&', -F/--form-string
                    build a multipart form; wget post/data; httpie and xh raw)
    body_file       the value names a file (or '-', stdin) the body is read from
    url             the value is a URL
    header          the value is a request header
    route_override  the request may land somewhere other than its URL says (a path, socket or address override)
    config_input    options, URLs or headers are read from a file
    template        curl --variable: defines what --expand-<option> substitutes
    session         httpie/xh --session: headers (Host among them) and auth are read from a session file
    get head next globoff         curl -G, -I, --next, -g
    noconfig recursive wgetrc     wget --no-config, -r/-m/-p, -e
    form ignore_stdin             httpie/xh --form/--multipart, --ignore-stdin
    field raw_field               gh api -F (typed: @file reads), -f (a literal string)

RESULT
    {"ok": bool,             every word was read under the client's table (no unknown option, no missing value)
     "requests": [{
        "method": str|None,  explicit (-X, --request, --method, httpie/xh's METHOD word) wins; else the method
                             the body implies (POST; PUT for curl -T; HEAD for curl -I; GET for curl -G); else GET.
                             None when it is not established (a refused combination, a non-token -X value, httpie
                             or xh with nothing pinning stdin).
        "urls": [str],       every URL the request goes to, as written (curl globs expanded, -G data appended)
        "body_pieces": [str],  each body option's value or request item, as given
        "body": str|None,    the body as sent, when this module can assemble it from inline pieces
        "fields": [str]|None,  the request parameters as key=value (a JSON-object body's top-level pairs, every
                             duplicate kept; httpie/xh data items; gh api -f/-F; curl -F); None when unreadable
        "body_unknown": bool,  part of the body or its parameters comes from a file, stdin or a template
        "route_override": bool,  the destination is not only the URL (see "routes")
        "routes": [str],     each override as written: "--connect-to a:443:b:443", "Host: x", "-H @file", ...
        "headers": [str]}],  each header option's value or header item, as given
     "unknown": bool,        targets_unknown, or any request whose method is None or whose body or route is unknown
     "targets_unknown": bool,  which requests are made -- their methods or URLs -- is not established
     "default_config": [str],  config files the client reads by default (a caller checks they are absent)
     "reasons": [str]}       why anything above is unknown, in the order found

    argv is the words after the program name, after the shell has done its work: this module knows nothing of
    quoting or expansion, so a caller marks a word it could not expand itself. Python 3.9+, stdlib only; parse()
    never raises (an internal error is reported as an unknown call).
"""

import itertools
import json
import re
from urllib.parse import quote

__all__ = ["parse", "TABLES", "Opt", "Table"]

ROLES = {"flag", "method", "body:data", "body:raw", "body:urlencode", "body:json", "body:form", "body:form_string",
         "body:post", "body_file", "body_file:post", "body_file:data", "url", "header", "route_override",
         "config_input", "template", "session", "get", "head", "next", "globoff", "noconfig", "recursive", "wgetrc",
         "form", "ignore_stdin", "field", "raw_field"}


class Opt(object):
    """One option of one client: its long name, its short letter (or None), whether it takes a value, its role,
    and (wget) the .wgetrc command that sets it when that is not the long name with '-' removed."""

    __slots__ = ("long", "short", "value", "role", "rc")

    def __init__(self, long_name, value, role, short=None, rc=None):
        self.long, self.value, self.role, self.short, self.rc = long_name, value, role, short, rc

    def __repr__(self):
        return "Opt(--%s%s, %s, %s)" % (self.long, " -" + self.short if self.short else "",
                                       "value" if self.value else "flag", self.role)


class Table(object):
    """A client's option table, read from its text block: one option a line,
    `long-name  v|-  role  short|.  [rc=wgetrc-command]`; '#' starts a comment line.

    negate:   None (pflag), "flags" (curl, getopt: --no-<flag> only), "all" (argparse, clap: --no-<any option>)
    prefixes: True when the grammar accepts an unambiguous prefix of a long name (getopt, argparse)"""

    def __init__(self, client, text, negate, prefixes, nflags=""):
        self.client, self.negate, self.prefixes, self.nflags = client, negate, prefixes, nflags
        self.opts, self.long, self.short = [], {}, {}
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            f = line.split()
            if len(f) < 4 or f[1] not in ("v", "-") or f[2] not in ROLES:
                raise ValueError("%s table: bad line %r" % (client, line))
            short = None if f[3] == "." else f[3]
            rc = f[4][3:] if len(f) > 4 and f[4].startswith("rc=") else None
            o = Opt(f[0], f[1] == "v", f[2], short, rc)
            if o.long in self.long or (short and short in self.short):
                raise ValueError("%s table: %s listed twice" % (client, o.long))
            self.long[o.long] = o
            if short:
                self.short[short] = o
            self.opts.append(o)

    def find_long(self, name):
        """(opt, negated) for --<name>; (None, "unknown") or (None, "ambiguous: ...") when there is none."""
        o = self.long.get(name)
        if o is not None:
            return o, False
        if self.negate and name.startswith("no-"):
            base = self.long.get(name[3:])
            if base is not None and (self.negate == "all" or not base.value):
                return base, True
        if self.prefixes and name:
            hits = {}
            for n, o in self.long.items():
                if n.startswith(name):
                    hits[n] = (o, False)
                # getopt lists every boolean's --no-<name> beside it, so a prefix can name one of those.
                if self.negate == "flags" and not o.value and ("no-" + n).startswith(name) \
                        and ("no-" + n) not in self.long:
                    hits["no-" + n] = (o, True)
            if len(hits) == 1:
                return list(hits.values())[0]
            if hits:
                return None, "ambiguous: " + ", ".join("--" + n for n in sorted(hits))
        return None, "unknown"


# ---------------------------------------------------------------------------------------------------------------
# curl 8.7.1 -- generated from `curl --help all`, then roles assigned. Its --help <category> is optional, so it is
# read as a flag (a word after it is a URL, which can only be stricter). Every --no-<name> curl lists is the
# negation of a boolean; curl accepts the positive name too, so those are listed below the generated block.
CURL_TEXT = """
# long                         v role             short
abstract-unix-socket           v route_override   .
alt-svc                        v route_override   .
anyauth                        - flag             .
append                         - flag             a
aws-sigv4                      v flag             .
basic                          - flag             .
ca-native                      - flag             .
cacert                         v flag             .
capath                         v flag             .
cert                           v flag             E
cert-status                    - flag             .
cert-type                      v flag             .
ciphers                        v flag             .
compressed                     - flag             .
compressed-ssh                 - flag             .
config                         v config_input     K
connect-timeout                v flag             .
connect-to                     v route_override   .
continue-at                    v flag             C
cookie                         v flag             b
cookie-jar                     v flag             c
create-dirs                    - flag             .
create-file-mode               v flag             .
crlf                           - flag             .
crlfile                        v flag             .
curves                         v flag             .
data                           v body:data        d
data-ascii                     v body:data        .
data-binary                    v body:data        .
data-raw                       v body:raw         .
data-urlencode                 v body:urlencode   .
delegation                     v flag             .
digest                         - flag             .
disable                        - flag             q
disable-eprt                   - flag             .
disable-epsv                   - flag             .
disallow-username-in-url       - flag             .
dns-interface                  v flag             .
dns-ipv4-addr                  v flag             .
dns-ipv6-addr                  v flag             .
dns-servers                    v flag             .
doh-cert-status                - flag             .
doh-insecure                   - flag             .
doh-url                        v flag             .
dump-header                    v flag             D
egd-file                       v flag             .
engine                         v flag             .
etag-compare                   v flag             .
etag-save                      v flag             .
expect100-timeout              v flag             .
fail                           - flag             f
fail-early                     - flag             .
fail-with-body                 - flag             .
false-start                    - flag             .
form                           v body:form        F
form-escape                    - flag             .
form-string                    v body:form_string .
ftp-account                    v flag             .
ftp-alternative-to-user        v flag             .
ftp-create-dirs                - flag             .
ftp-method                     v flag             .
ftp-pasv                       - flag             .
ftp-port                       v flag             P
ftp-pret                       - flag             .
ftp-skip-pasv-ip               - flag             .
ftp-ssl-ccc                    - flag             .
ftp-ssl-ccc-mode               v flag             .
ftp-ssl-control                - flag             .
get                            - get              G
globoff                        - globoff          g
happy-eyeballs-timeout-ms      v flag             .
haproxy-clientip               v flag             .
haproxy-protocol               - flag             .
head                           - head             I
header                         v header           H
help                           - flag             h
hostpubmd5                     v flag             .
hostpubsha256                  v flag             .
hsts                           v flag             .
http0.9                        - flag             .
http1.0                        - flag             0
http1.1                        - flag             .
http2                          - flag             .
http2-prior-knowledge          - flag             .
http3                          - flag             .
http3-only                     - flag             .
ignore-content-length          - flag             .
include                        - flag             i
insecure                       - flag             k
interface                      v flag             .
ipfs-gateway                   v flag             .
ipv4                           - flag             4
ipv6                           - flag             6
json                           v body:json        .
junk-session-cookies           - flag             j
keepalive-time                 v flag             .
key                            v flag             .
key-type                       v flag             .
krb                            v flag             .
libcurl                        v flag             .
limit-rate                     v flag             .
list-only                      - flag             l
local-port                     v flag             .
location                       - flag             L
location-trusted               - flag             .
login-options                  v flag             .
mail-auth                      v flag             .
mail-from                      v flag             .
mail-rcpt                      v flag             .
mail-rcpt-allowfails           - flag             .
manual                         - flag             M
max-filesize                   v flag             .
max-redirs                     v flag             .
max-time                       v flag             m
metalink                       - flag             .
negotiate                      - flag             .
netrc                          - flag             n
netrc-file                     v flag             .
netrc-optional                 - flag             .
next                           - next             :
no-alpn                        - flag             .
no-buffer                      - flag             N
no-clobber                     - flag             .
no-keepalive                   - flag             .
no-npn                         - flag             .
no-progress-meter              - flag             .
no-sessionid                   - flag             .
noproxy                        v flag             .
ntlm                           - flag             .
ntlm-wb                        - flag             .
oauth2-bearer                  v flag             .
output                         v flag             o
output-dir                     v flag             .
parallel                       - flag             Z
parallel-immediate             - flag             .
parallel-max                   v flag             .
pass                           v flag             .
path-as-is                     - flag             .
pinnedpubkey                   v flag             .
post301                        - flag             .
post302                        - flag             .
post303                        - flag             .
preproxy                       v flag             .
progress-bar                   - flag             #
proto                          v flag             .
proto-default                  v flag             .
proto-redir                    v flag             .
proxy                          v flag             x
proxy-anyauth                  - flag             .
proxy-basic                    - flag             .
proxy-ca-native                - flag             .
proxy-cacert                   v flag             .
proxy-capath                   v flag             .
proxy-cert                     v flag             .
proxy-cert-type                v flag             .
proxy-ciphers                  v flag             .
proxy-crlfile                  v flag             .
proxy-digest                   - flag             .
proxy-header                   v flag             .
proxy-http2                    - flag             .
proxy-insecure                 - flag             .
proxy-key                      v flag             .
proxy-key-type                 v flag             .
proxy-negotiate                - flag             .
proxy-ntlm                     - flag             .
proxy-pass                     v flag             .
proxy-pinnedpubkey             v flag             .
proxy-service-name             v flag             .
proxy-ssl-allow-beast          - flag             .
proxy-ssl-auto-client-cert     - flag             .
proxy-tls13-ciphers            v flag             .
proxy-tlsauthtype              v flag             .
proxy-tlspassword              v flag             .
proxy-tlsuser                  v flag             .
proxy-tlsv1                    - flag             .
proxy-user                     v flag             U
proxy1.0                       v flag             .
proxytunnel                    - flag             p
pubkey                         v flag             .
quote                          v flag             Q
random-file                    v flag             .
range                          v flag             r
rate                           v flag             .
raw                            - flag             .
referer                        v flag             e
remote-header-name             - flag             J
remote-name                    - flag             O
remote-name-all                - flag             .
remote-time                    - flag             R
remove-on-error                - flag             .
request                        v method           X
request-target                 v route_override   .
resolve                        v route_override   .
retry                          v flag             .
retry-all-errors               - flag             .
retry-connrefused              - flag             .
retry-delay                    v flag             .
retry-max-time                 v flag             .
sasl-authzid                   v flag             .
sasl-ir                        - flag             .
service-name                   v flag             .
show-error                     - flag             S
silent                         - flag             s
socks4                         v flag             .
socks4a                        v flag             .
socks5                         v flag             .
socks5-basic                   - flag             .
socks5-gssapi                  - flag             .
socks5-gssapi-nec              - flag             .
socks5-gssapi-service          v flag             .
socks5-hostname                v flag             .
speed-limit                    v flag             Y
speed-time                     v flag             y
ssl                            - flag             .
ssl-allow-beast                - flag             .
ssl-auto-client-cert           - flag             .
ssl-no-revoke                  - flag             .
ssl-reqd                       - flag             .
ssl-revoke-best-effort         - flag             .
sslv2                          - flag             2
sslv3                          - flag             3
stderr                         v flag             .
styled-output                  - flag             .
suppress-connect-headers       - flag             .
tcp-fastopen                   - flag             .
tcp-nodelay                    - flag             .
telnet-option                  v flag             t
tftp-blksize                   v flag             .
tftp-no-options                - flag             .
time-cond                      v flag             z
tls-max                        v flag             .
tls13-ciphers                  v flag             .
tlsauthtype                    v flag             .
tlspassword                    v flag             .
tlsuser                        v flag             .
tlsv1                          - flag             1
tlsv1.0                        - flag             .
tlsv1.1                        - flag             .
tlsv1.2                        - flag             .
tlsv1.3                        - flag             .
tr-encoding                    - flag             .
trace                          v flag             .
trace-ascii                    v flag             .
trace-config                   v flag             .
trace-ids                      - flag             .
trace-time                     - flag             .
unix-socket                    v route_override   .
upload-file                    v body_file        T
url                            v url              .
url-query                      v flag             .
use-ascii                      - flag             B
user                           v flag             u
user-agent                     v flag             A
variable                       v template         .
verbose                        - flag             v
version                        - flag             V
write-out                      v flag             w
xattr                          - flag             .
# accepted by curl 8.7.1 without being listed by --help all (probed: each runs, none takes a value)
alpn                           - flag             .
buffer                         - flag             .
clobber                        - flag             .
eprt                           - flag             .
epsv                           - flag             .
keepalive                      - flag             .
npn                            - flag             .
progress-meter                 - flag             .
sessionid                      - flag             .
ftp-ssl                        - flag             .
ftp-ssl-reqd                   - flag             .
# added after 8.7.1 (curl changelog): 8.8 ech; 8.9 ip-tos, vlan-priority, mptcp, keepalive-cnt; 8.10
# skip-existing, show-headers, dump-ca-embed; 8.11 tls-earlydata; 8.12 ssl-sessions; 8.13 upload-flags; 8.14
# sigalgs; 8.16 follow, out-null, parallel-max-host; 8.17 knownhosts
ech                            v flag             .
ip-tos                         v flag             .
vlan-priority                  v flag             .
mptcp                          - flag             .
keepalive-cnt                  v flag             .
skip-existing                  - flag             .
show-headers                   - flag             .
dump-ca-embed                  - flag             .
tls-earlydata                  - flag             .
ssl-sessions                   v flag             .
upload-flags                   v flag             .
sigalgs                        v flag             .
follow                         - flag             .
out-null                       - flag             .
parallel-max-host              v flag             .
knownhosts                     v flag             .
"""

# ---------------------------------------------------------------------------------------------------------------
# GNU Wget 1.24.5 -- hand-listed from `wget --help`. getopt_long: a long option may be abbreviated to any
# unambiguous prefix, a boolean takes an optional attached value (--recursive=off) and has a --no-<name> twin.
# -n takes letters (-nv -nc -nd -nH -np); `rc=` names the .wgetrc command -e sets when it is not the long name.
WGET_TEXT = """
# long                         v role             short rc
version                        - flag             V
help                           - flag             h
background                     - flag             b
execute                        v wgetrc           e
output-file                    v flag             o     rc=logfile
append-output                  v flag             a
debug                          - flag             d
quiet                          - flag             q
verbose                        - flag             v
no-verbose                     - flag             .
report-speed                   v flag             .
input-file                     v config_input     i     rc=input
input-metalink                 v config_input     .
force-html                     - flag             F
base                           v flag             B
config                         v config_input     .     rc=chooseconfig
no-config                      - noconfig         .
rejected-log                   v flag             .
tries                          v flag             t
retry-connrefused              - flag             .
retry-on-host-error            - flag             .
retry-on-http-error            v flag             .
output-document                v flag             O
no-clobber                     - flag             .
no-netrc                       - flag             .
continue                       - flag             c
start-pos                      v flag             .
progress                       v flag             .
show-progress                  - flag             .
timestamping                   - flag             N
no-if-modified-since           - flag             .
no-use-server-timestamps       - flag             .
server-response                - flag             S
spider                         - flag             .
timeout                        v flag             T
dns-servers                    v flag             .
bind-dns-address               v flag             .
dns-timeout                    v flag             .
connect-timeout                v flag             .
read-timeout                   v flag             .
wait                           v flag             w
waitretry                      v flag             .
random-wait                    - flag             .
no-proxy                       - flag             .
quota                          v flag             Q
bind-address                   v flag             .
limit-rate                     v flag             .
no-dns-cache                   - flag             .
restrict-file-names            v flag             .
ignore-case                    - flag             .
inet4-only                     - flag             4
inet6-only                     - flag             6
prefer-family                  v flag             .
user                           v flag             .
password                       v flag             .
ask-password                   - flag             .
use-askpass                    v flag             .
no-iri                         - flag             .
local-encoding                 v flag             .
remote-encoding                v flag             .
unlink                         - flag             .
keep-badhash                   - flag             .
metalink-index                 v flag             .
metalink-over-http             - flag             .
preferred-location             v flag             .
no-xattr                       - flag             .
no-directories                 - flag             .
force-directories              - flag             x
no-host-directories            - flag             .
protocol-directories           - flag             .
directory-prefix               v flag             P     rc=dirprefix
cut-dirs                       v flag             .
http-user                      v flag             .
http-password                  v flag             .
no-cache                       - flag             .
default-page                   v flag             .
adjust-extension               - flag             E
ignore-length                  - flag             .
header                         v header           .
compression                    v flag             .
max-redirect                   v flag             .
proxy-user                     v flag             .
proxy-password                 v flag             .
referer                        v flag             .
save-headers                   - flag             .
user-agent                     v flag             U
no-http-keep-alive             - flag             .
no-cookies                     - flag             .
load-cookies                   v flag             .
save-cookies                   v flag             .
keep-session-cookies           - flag             .
post-data                      v body:post        .
post-file                      v body_file:post   .
method                         v method           .
body-data                      v body:data        .
body-file                      v body_file:data   .
content-disposition            - flag             .
content-on-error               - flag             .
auth-no-challenge              - flag             .
secure-protocol                v flag             .
https-only                     - flag             .
no-check-certificate           - flag             .
certificate                    v flag             .
certificate-type               v flag             .
private-key                    v flag             .
private-key-type               v flag             .
ca-certificate                 v flag             .
ca-directory                   v flag             .
crl-file                       v flag             .
pinnedpubkey                   v flag             .
random-file                    v flag             .
ciphers                        v flag             .
no-hsts                        - flag             .
hsts-file                      v flag             .
ftp-user                       v flag             .
ftp-password                   v flag             .
no-remove-listing              - flag             .
no-glob                        - flag             .
no-passive-ftp                 - flag             .
preserve-permissions           - flag             .
retr-symlinks                  - flag             .
ftps-implicit                  - flag             .
ftps-resume-ssl                - flag             .
ftps-clear-data-connection     - flag             .
ftps-fallback-to-ftp           - flag             .
warc-file                      v flag             .
warc-header                    v flag             .
warc-max-size                  v flag             .
warc-cdx                       - flag             .
warc-dedup                     v flag             .
no-warc-compression            - flag             .
no-warc-digests                - flag             .
no-warc-keep-log               - flag             .
warc-tempdir                   v flag             .
recursive                      - recursive        r
level                          v flag             l     rc=reclevel
delete-after                   - flag             .
convert-links                  - flag             k
convert-file-only              - flag             .
backups                        v flag             .
backup-converted               - flag             K
mirror                         - recursive        m
page-requisites                - recursive        p
strict-comments                - flag             .
accept                         v flag             A
reject                         v flag             R
accept-regex                   v flag             .
reject-regex                   v flag             .
regex-type                     v flag             .
domains                        v flag             D
exclude-domains                v flag             .
follow-ftp                     - flag             .
follow-tags                    v flag             .
ignore-tags                    v flag             .
span-hosts                     - flag             H
relative                       - flag             L     rc=relativeonly
include-directories            v flag             I
trust-server-names             - flag             .
exclude-directories            v flag             X
no-parent                      - flag             .
"""
# .wgetrc commands -e accepts that are no long option's name; none of them shapes what is sent.
WGET_RC_ONLY = ("robots", "httpproxy", "httpsproxy", "ftpproxy", "useproxy", "addhostdir", "dirstruct", "htmlextension",
                "checkcertificate", "httpkeepalive", "passiveftp", "removelisting", "glob", "iri", "dnscache", "hsts",
                "xattr", "netrc", "cache", "cookies", "ifmodifiedsince", "useservertimestamps", "noclobber")

# ---------------------------------------------------------------------------------------------------------------
# HTTPie 3.2.4 -- hand-listed from `http --help`. argparse: a long option may be abbreviated; every option has a
# --no-<name> that resets it and takes no value. Positionals: [METHOD] URL [REQUEST_ITEM ...].
HTTPIE_TEXT = """
json                           - flag             j
form                           - form             f
multipart                      - form             .
boundary                       v flag             .
raw                            v body:raw         .
compress                       - flag             x
pretty                         v flag             .
style                          v flag             s
unsorted                       - flag             .
sorted                         - flag             .
response-charset               v flag             .
response-mime                  v flag             .
format-options                 v flag             .
print                          v flag             p
headers                        - flag             h
meta                           - flag             m
body                           - flag             b
verbose                        - flag             v
all                            - flag             .
history-print                  v flag             P
stream                         - flag             S
output                         v flag             o
download                       - flag             d
continue                       - flag             c
quiet                          - flag             q
session                        v session          .
session-read-only              v session          .
auth                           v flag             a
auth-type                      v flag             A
ignore-netrc                   - flag             .
offline                        - flag             .
proxy                          v flag             .
follow                         - flag             F
max-redirects                  v flag             .
max-headers                    v flag             .
timeout                        v flag             .
check-status                   - flag             .
path-as-is                     - flag             .
chunked                        - flag             .
verify                         v flag             .
ssl                            v flag             .
ciphers                        v flag             .
cert                           v flag             .
cert-key                       v flag             .
cert-key-pass                  v flag             .
ignore-stdin                   - ignore_stdin     I
help                           - flag             .
manual                         - flag             .
version                        - flag             .
traceback                      - flag             .
default-scheme                 v flag             .
debug                          - flag             .
"""

# ---------------------------------------------------------------------------------------------------------------
# xh 0.24 -- hand-listed from `xh --help`. clap: exact long names, -o=v and -ov attached, --no-<name> resets any
# option. Positionals as httpie's.
XH_TEXT = """
json                           - flag             j
form                           - form             f
multipart                      - form             .
raw                            v body:raw         .
pretty                         v flag             .
format-options                 v flag             .
style                          v flag             s
response-charset               v flag             .
response-mime                  v flag             .
print                          v flag             p
headers                        - flag             h
body                           - flag             b
meta                           - flag             m
verbose                        - flag             v
debug                          - flag             .
all                            - flag             .
history-print                  v flag             P
quiet                          - flag             q
stream                         - flag             S
compress                       - flag             x
output                         v flag             o
download                       - flag             d
continue                       - flag             c
session                        v session          .
session-read-only              v session          .
auth-type                      v flag             A
auth                           v flag             a
bearer                         v flag             .
ignore-netrc                   - flag             .
offline                        - flag             .
check-status                   - flag             .
follow                         - flag             F
max-redirects                  v flag             .
timeout                        v flag             .
proxy                          v flag             .
verify                         v flag             .
cert                           v flag             .
cert-key                       v flag             .
ssl                            v flag             .
native-tls                     - flag             .
default-scheme                 v flag             .
https                          - flag             .
http-version                   v flag             .
resolve                        v route_override   .
interface                      v flag             .
ipv4                           - flag             4
ipv6                           - flag             6
unix-socket                    v route_override   .
ignore-stdin                   - ignore_stdin     I
curl                           - flag             .
curl-long                      - flag             .
generate                       v flag             .
path-as-is                     - flag             .
sorted                         - flag             .
unsorted                       - flag             .
help                           - flag             .
version                        - flag             V
"""

# ---------------------------------------------------------------------------------------------------------------
# gh 2.103.3 `gh api --help`. pflag: exact long names, --name=v or --name v, -Xv / -X=v / -X v, clusters (-iXPOST),
# --flag=false for a boolean; no --no-<name>. -h/--help is cobra's.
GH_API_TEXT = """
allow-escape-sequences         - flag             .
cache                          v flag             .
field                          v field            F
header                         v header           H
hostname                       v flag             .
include                        - flag             i
input                          v body_file        .
jq                             v flag             q
method                         v method           X
paginate                       - flag             .
preview                        v flag             p
raw-field                      v raw_field        f
silent                         - flag             .
slurp                          - flag             .
template                       v flag             t
verbose                        - flag             .
help                           - flag             h
"""

CURL = Table("curl", CURL_TEXT, negate="flags", prefixes=False)
WGET = Table("wget", WGET_TEXT, negate="flags", prefixes=True, nflags="vcdHp")
HTTPIE = Table("httpie", HTTPIE_TEXT, negate="all", prefixes=True)
XH = Table("xh", XH_TEXT, negate="all", prefixes=False)
GH_API = Table("gh api", GH_API_TEXT, negate=None, prefixes=False)
TABLES = {"curl": CURL, "wget": WGET, "httpie": HTTPIE, "xh": XH, "gh api": GH_API}
STYLE = {"curl": "curl", "wget": "getopt", "httpie": "argparse", "xh": "clap", "gh api": "pflag"}

# The program word -> the client; `https`/`xhs` only change the default scheme.
CLIENTS = {"curl": "curl", "wget": "wget", "http": "httpie", "https": "httpie", "xh": "xh", "xhs": "xh",
           "gh api": "gh api"}

DEFAULT_CONFIG = {
    "curl": ["$CURL_HOME/.curlrc", "$XDG_CONFIG_HOME/curlrc", "~/.curlrc"],
    "wget": ["$WGETRC", "~/.wgetrc", "/etc/wgetrc", "/usr/local/etc/wgetrc"],
    "httpie": ["$HTTPIE_CONFIG_DIR/config.json", "$XDG_CONFIG_HOME/httpie/config.json", "~/.config/httpie/config.json"],
    "xh": ["$XH_CONFIG_DIR/config.json", "$XDG_CONFIG_HOME/xh/config.json", "~/.config/xh/config.json",
           "~/Library/Application Support/xh/config.json"],
    "gh api": [],
}


def _dehyphen(name):
    return re.sub(r"[-_\s]", "", name).lower()


WGET_RC = {}
for _o in WGET.opts:
    WGET_RC.setdefault(_o.rc or _dehyphen(_o.long), _o)
for _n in WGET_RC_ONLY:
    WGET_RC.setdefault(_n, Opt(_n, False, "flag"))


# ---------------------------------------------------------------------------------------------------------------
# The readers: one walk of the words per option grammar, yielding
#   ("pos", word)                                              a positional (a URL, a METHOD, a request item)
#   ("opt", opt, value|None, negated, spelled, expanded)       an option the table lists
#   ("unknown", text, why) / ("missing", spelled)              a word the table cannot read / a value that is absent

def _falsy(v):
    return v.strip().lower() in ("off", "no", "0", "false")


def _words(table, argv, style):
    n, i = len(argv), 0
    while i < n:
        w = argv[i]
        i += 1
        if w == "--":
            for x in argv[i:]:
                yield ("pos", x)
            return
        if w.startswith("--"):
            name, eq, val = w[2:].partition("=")
            expanded = False
            if style == "curl" and name.startswith("expand-") and len(name) > 7:
                expanded, name = True, name[7:]   # curl 8.3+: --expand-<option> is <option> with {{variables}}
            opt, neg = table.find_long(name)
            if opt is None:
                yield ("unknown", w, neg)
                continue
            if expanded and (not opt.value or neg):
                yield ("unknown", w, "--expand- takes an option with a value")
                continue
            if opt.value and not neg:
                if eq:
                    value = val   # curl itself refuses --opt=value; reading it as the value is the stricter side
                elif i < n:
                    value, i = argv[i], i + 1
                else:
                    yield ("missing", w)
                    continue
                yield ("opt", opt, value, False, "--" + opt.long, expanded)
            elif opt.value:
                # --no-<value option>: curl refuses it; argparse and clap reset the option.
                if style == "curl":
                    yield ("unknown", w, "curl takes --no- only on a boolean")
                else:
                    yield ("opt", opt, None, True, w, False)
            elif eq:
                if style in ("getopt", "pflag"):   # --recursive=off, --include=false
                    yield ("opt", opt, None, neg != _falsy(val), "--" + opt.long, False)
                else:
                    yield ("unknown", w, "a flag given a value")
            else:
                yield ("opt", opt, None, neg, w, False)
            continue
        if w.startswith("-") and len(w) > 1:
            j = 1
            while j < len(w):
                ch = w[j]
                if style == "getopt" and ch == "n" and table.nflags:
                    letters = w[j + 1:]
                    if not letters:
                        if i >= n:
                            yield ("missing", "-n")
                            break
                        letters, i = argv[i], i + 1
                    if not letters or any(c not in table.nflags for c in letters):
                        yield ("unknown", "-n" + letters, "wget -n takes only the letters " + table.nflags)
                    break
                opt = table.short.get(ch)
                if opt is None:
                    yield ("unknown", "-" + ch + (" (in %s)" % w if len(w) > 2 else ""), "unknown")
                    break
                if opt.value:
                    value = w[j + 1:]
                    if not value:
                        if i >= n:
                            yield ("missing", "-" + ch)
                            break
                        value, i = argv[i], i + 1
                    elif value.startswith("=") and style in ("argparse", "clap", "pflag"):
                        value = value[1:]   # -X=POST, -f=k=v
                    yield ("opt", opt, value, False, "-" + ch, False)
                    break
                if style == "pflag" and w[j + 1:j + 2] == "=":
                    yield ("opt", opt, None, _falsy(w[j + 2:]), "-" + ch, False)
                    break
                yield ("opt", opt, None, False, "-" + ch, False)
                j += 1
            continue
        yield ("pos", w)


# ---------------------------------------------------------------------------------------------------------------
# What the readers found, and the facts every client shares.

class _Out(object):
    def __init__(self):
        self.ok, self.targets = True, False
        self.reasons, self.requests, self.default_config = [], [], []

    def why(self, text):
        if text not in self.reasons:
            self.reasons.append(text)

    def target(self, text):
        """Which requests are made -- their methods or URLs -- is not established."""
        self.targets = True
        self.why(text)

    def broken(self, text):
        """A word could not be read under the client's table."""
        self.ok = False
        self.target(text)

    def bad_word(self, ev, client):
        if ev[0] == "unknown":
            why = "" if ev[2] == "unknown" else " (%s)" % ev[2]
            self.broken("%s: %s is not an option this table lists%s; it may take the next word, which may be the "
                        "URL" % (client, ev[1], why))
        else:
            self.broken("%s: %s has no value" % (client, ev[1]))

    def add(self, method, urls, pieces, body, fields, unknown_body, routes, headers):
        for r in unknown_body:
            self.why(r)
        for r in routes:
            self.why("the destination is not only the URL: " + r)
        self.requests.append({
            "method": method, "urls": list(urls), "body_pieces": list(pieces),
            "body": None if unknown_body else body, "fields": None if unknown_body else fields,
            "body_unknown": bool(unknown_body), "route_override": bool(routes), "routes": list(routes),
            "headers": list(headers)})

    def result(self):
        unknown = self.targets or any(q["method"] is None or q["body_unknown"] or q["route_override"]
                                      for q in self.requests)
        return {"ok": self.ok, "requests": self.requests, "unknown": unknown, "targets_unknown": self.targets,
                "default_config": list(self.default_config), "reasons": list(self.reasons)}


METHOD_TOKEN = re.compile(r"\A[A-Za-z]+\Z")


def _method(value, spelled, out):
    if METHOD_TOKEN.match(value):
        return value.upper()
    out.target("%s %r is not a plain method name" % (spelled, value))
    return None


def _host_header(text):
    """A header that names the Host, carries a line break, or (curl) is read from a file re-targets the request."""
    name = re.split(r"[:;]", text, 1)[0].strip().lower()
    return name == "host" or "\r" in text or "\n" in text


class _Pairs(list):
    pass


def _plain(v):
    if isinstance(v, _Pairs):
        return dict((k, _plain(x)) for k, x in v)
    if isinstance(v, list):
        return [_plain(x) for x in v]
    return v


def _json_fields(text):
    """A JSON object's top-level key=value pairs (a string value as itself, any other value as JSON), every
    duplicate key kept -- a server may read either -- or None when the text is not a JSON object."""
    if text is None:
        return None
    try:
        doc = json.loads(text, object_pairs_hook=_Pairs)
    except ValueError:
        return None
    if not isinstance(doc, _Pairs):
        return None
    return ["%s=%s" % (k, v if isinstance(v, str) else json.dumps(_plain(v), separators=(",", ":")))
            for k, v in doc]


# ---------------------------------------------------------------------------------------------------------------
# curl

GLOB_LIMIT = 256
GLOB_IPV6 = re.compile(r"\A[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*(%[0-9A-Za-z._~-]+)?\Z")
GLOB_NUM = re.compile(r"\A(\d+)-(\d+)(?::(\d+))?\Z")
GLOB_ALPHA = re.compile(r"\A([A-Za-z])-([A-Za-z])(?::(\d+))?\Z")


def _glob_range(body):
    m = GLOB_NUM.match(body)
    if m:
        lo, hi, step = int(m.group(1)), int(m.group(2)), int(m.group(3) or 1)
        if step < 1 or hi < lo or (hi - lo) // step + 1 > GLOB_LIMIT:
            return None
        width = len(m.group(1)) if m.group(1).startswith("0") else 0
        return [str(v).zfill(width) for v in range(lo, hi + 1, step)]
    m = GLOB_ALPHA.match(body)
    if m:
        lo, hi, step = m.group(1), m.group(2), int(m.group(3) or 1)
        if step < 1 or hi < lo or lo.isupper() != hi.isupper():
            return None
        return [chr(c) for c in range(ord(lo), ord(hi) + 1, step)]
    return None


def _curl_glob(url):
    """The URLs a curl URL glob names ({a,b} sets, [1-3] / [a-c] / [01-10:2] ranges; a backslash escapes a glob
    character; an IPv6 [address] is literal), or None when curl would refuse it or it names more than GLOB_LIMIT."""
    parts, lit, i, n = [], [], 0, len(url)
    while i < n:
        c = url[i]
        if c == "\\" and i + 1 < n and url[i + 1] in "{}[]":
            lit.append(url[i + 1])
            i += 2
            continue
        if c == "{":
            alts, cur, j = [], [], i + 1
            while j < n and url[j] != "}":
                ch = url[j]
                if ch == "\\" and j + 1 < n:
                    cur.append(url[j + 1])
                    j += 2
                    continue
                if ch in "{[":
                    return None   # curl refuses a nested glob
                if ch == ",":
                    alts.append("".join(cur))
                    cur = []
                else:
                    cur.append(ch)
                j += 1
            if j >= n:
                return None
            alts.append("".join(cur))
            parts += [["".join(lit)], alts]
            lit, i = [], j + 1
            continue
        if c == "[":
            j = url.find("]", i + 1)
            if j < 0:
                return None
            body = url[i + 1:j]
            if GLOB_IPV6.match(body):
                lit.append(url[i:j + 1])
            else:
                alts = _glob_range(body)
                if alts is None:
                    return None
                parts += [["".join(lit)], alts]
                lit = []
            i = j + 1
            continue
        if c in "}]":
            return None
        lit.append(c)
        i += 1
    parts.append(["".join(lit)])
    total = 1
    for p in parts:
        total *= len(p)
        if total > GLOB_LIMIT:
            return None
    return ["".join(x) for x in itertools.product(*parts)]


DATA_KINDS = ("data", "raw", "urlencode", "json")
FORM_KINDS = ("form", "form_string")


def _curl_piece(kind, val):
    """The text one data piece adds to the body, or None when curl reads it from a file or stdin."""
    if kind in ("data", "json"):
        return None if val.startswith("@") else val
    if kind == "raw":
        return val
    # --data-urlencode: content | =content | name=content | @file | name@file ('=' is looked for before '@')
    cut = val.find("=")
    if cut < 0:
        cut = val.find("@")
    if cut < 0:
        return quote(val, safe="")
    name, sep, content = val[:cut], val[cut], val[cut + 1:]
    if sep == "@":
        return None
    return (name + "=" if name else "") + quote(content, safe="")


def _curl_join(data):
    """curl's body from its data pieces: each joined to the one before with '&', except a --json piece, which is
    appended as it is (measured against curl 8.7.1). None when a piece is read from a file or is a template."""
    text = []
    for k, (kind, val, _spelled, templ) in enumerate(data):
        piece = None if templ else _curl_piece(kind, val)
        if piece is None:
            return None
        if k and kind != "json":
            text.append("&")
        text.append(piece)
    return "".join(text)


class _CurlGroup(object):
    def __init__(self):
        self.urls, self.pieces, self.uploads, self.headers, self.routes, self.unknown_body = [], [], [], [], [], []
        self.method, self.get, self.head, self.globoff = None, False, False, False


def _curl(argv, out):
    if argv[:1] not in (["-q"], ["--disable"]):   # only a first -q stops curl reading its curlrc
        out.default_config = list(DEFAULT_CONFIG["curl"])
    groups = [_CurlGroup()]
    for ev in _words(CURL, argv, "curl"):
        g = groups[-1]
        if ev[0] == "pos":
            g.urls.append(ev[1])
            continue
        if ev[0] != "opt":
            out.bad_word(ev, "curl")
            continue
        _, opt, value, neg, spelled, expanded = ev
        role = opt.role
        templ = expanded and "{{" in value
        spelled = ("--expand-" + opt.long) if expanded else spelled
        if templ and role in ("method", "url", "config_input"):
            out.target("curl %s %r is a {{variable}} template curl fills in at run time" % (spelled, value))
        if role == "method":
            g.method = (value, spelled, templ)
        elif role.startswith("body:"):
            g.pieces.append((role[5:], value, spelled, templ))
            if templ:
                g.unknown_body.append("curl %s holds a {{variable}} template: the body is filled in at run time"
                                      % spelled)
        elif role == "body_file":
            g.uploads.append(value)
        elif role == "url":
            if value.startswith("@"):
                out.target("curl --url @file (curl 8.13+) reads URLs from a file")
            g.urls.append(value)
        elif role == "header":
            g.headers.append(value)
            if templ or value.startswith("@") or _host_header(value):
                g.routes.append("%s %s" % (spelled, value))
        elif role == "route_override":
            g.routes.append("%s %s" % (spelled, value))
        elif role == "config_input":
            out.target("curl %s reads options, URLs and headers from a file" % spelled)
        elif role == "get":
            g.get = not neg
        elif role == "head":
            g.head = not neg
        elif role == "globoff":
            g.globoff = not neg
        elif role == "next":
            if neg:
                out.broken("curl refuses --no-next")
            else:
                groups.append(_CurlGroup())
    if len(groups) > 1:
        for k, g in enumerate(groups):
            if not g.urls:
                out.target("curl --next group %d names no URL: curl refuses the command" % (k + 1))
    for g in groups:
        if g.urls:
            _curl_request(g, out)


def _curl_request(g, out):
    urls = []
    for u in g.urls:
        got = [u] if g.globoff else _curl_glob(u)
        if got is None:
            out.target("curl URL %r is a glob curl refuses or one naming more than %d URLs" % (u, GLOB_LIMIT))
            got = [u]
        urls += got
    data = [p for p in g.pieces if p[0] in DATA_KINDS]
    form = [p for p in g.pieces if p[0] in FORM_KINDS]
    unknown_body = list(g.unknown_body)
    # One transfer sends one kind of request. -G turns data into the query; it leaves -F (still a POST) and -T
    # (still a PUT) alone. Two kinds at once curl refuses (curl 8.7.1: -T with -d, -d with -F, -I with -d).
    modes = [m for m, on in (("data", data and not g.get), ("form", form), ("upload", g.uploads),
                             ("head", g.head)) if on]
    method = None
    if len(modes) > 1:
        out.target("curl refuses one transfer that is %s at once" % " and ".join(modes))
    elif g.method:
        method = None if g.method[2] else _method(g.method[0], "curl " + g.method[1], out)
    else:
        method = {"data": "POST", "form": "POST", "upload": "PUT", "head": "HEAD"}.get(modes[0] if modes else "",
                                                                                     "GET")
    body = fields = None
    joined = _curl_join(data) if data else None
    if data and g.get:
        if joined is None:
            unknown_body.append("curl -G puts data read from a file or a template into the URL")
        else:
            urls = [u + ("&" if "?" in u else "?") + joined for u in urls]
    if g.uploads:
        unknown_body.append("curl -T/--upload-file sends a file (or stdin) as the body")
    elif form:
        fields = []
        for kind, val, spelled, _t in form:
            name, eq, content = val.partition("=")
            if not eq:
                out.target("curl %s %r has no '=': curl refuses it" % (spelled, val))
            elif kind == "form" and content[:1] in ("@", "<"):
                unknown_body.append("curl %s %s=%s... reads a form part from a file" % (spelled, name, content[:1]))
            fields.append(val)
    elif data and not g.get:
        if joined is None:
            unknown_body.append("curl reads part of the body from a file or stdin (@file, @-)")
        body, fields = joined, _json_fields(joined)
    out.add(method, urls, [p[1] for p in g.pieces], body, fields, unknown_body, g.routes, g.headers)


# ---------------------------------------------------------------------------------------------------------------
# wget

def _wget(argv, out):
    s = {"method": None, "post": [], "post_file": [], "data": [], "data_file": [], "recursive": False,
         "noconfig": False, "config": False, "urls": [], "headers": [], "routes": [], "pieces": []}

    def apply(opt, value, neg, spelled):
        role = opt.role
        if role == "method":
            s["method"] = (value, spelled)
        elif role in ("body:post", "body:data"):
            s["post" if role == "body:post" else "data"].append(value)
            s["pieces"].append(value)
        elif role in ("body_file:post", "body_file:data"):
            s["post_file" if role == "body_file:post" else "data_file"].append(value)
            s["pieces"].append(value)
        elif role == "header":
            s["headers"].append(value)
            if _host_header(value):
                s["routes"].append("%s %s" % (spelled, value))
        elif role == "config_input":
            s["config"] = s["config"] or opt.long == "config"
            out.target("wget %s reads URLs or options from a file" % spelled)
        elif role == "noconfig":
            s["noconfig"] = not neg
        elif role == "recursive":
            s["recursive"] = not neg
        elif role == "wgetrc":
            key, eq, val = value.partition("=")
            rc = WGET_RC.get(_dehyphen(key))
            if not eq or not key.strip():
                out.broken("wget -e %r is not a 'command = value' line: wget refuses it" % value)
            elif rc is None or rc.role == "wgetrc":
                out.broken("wget -e %s: a .wgetrc command this table does not list" % key.strip())
            else:
                apply(rc, val.strip() if rc.value else None, (not rc.value) and _falsy(val), "-e " + key.strip())

    for ev in _words(WGET, argv, "getopt"):
        if ev[0] == "pos":
            s["urls"].append(ev[1])
        elif ev[0] == "opt":
            apply(ev[1], ev[2], ev[3], ev[4])
        else:
            out.bad_word(ev, "wget")
    if not s["noconfig"] and not s["config"]:
        out.default_config = list(DEFAULT_CONFIG["wget"])
    inline, files = s["post"] + s["data"], s["post_file"] + s["data_file"]
    if (s["post"] or s["post_file"]) and (s["data"] or s["data_file"]) or (s["post"] and s["post_file"]) \
            or (s["data"] and s["data_file"]):
        out.target("wget refuses more than one of --post-data, --post-file, --body-data, --body-file")
    if s["method"]:
        method = _method(s["method"][0], "wget " + s["method"][1], out)
    elif s["post"] or s["post_file"]:
        method = "POST"
    elif s["data"] or s["data_file"]:
        method = None
        out.target("wget --body-data/--body-file without --method: wget refuses")
    else:
        method = "GET"
    unknown_body, body = [], None
    if files:
        unknown_body.append("wget --post-file/--body-file sends a file as the body")
    elif inline:
        body = inline[-1]   # wget keeps the last value of an option given twice
    if s["recursive"] and (method != "GET" or inline or files):
        out.target("wget -r/-m/-p also requests the links it finds, under the same method and body")
    if s["urls"]:
        out.add(method, s["urls"], s["pieces"], body, _json_fields(body), unknown_body, s["routes"], s["headers"])


# ---------------------------------------------------------------------------------------------------------------
# httpie and xh: [METHOD] URL [REQUEST_ITEM ...]

ITEM_SEPS = (":=@", "==@", "=@", ":=", "==", ":@", "=", ":", ";", "@")   # longest first at each position
HEADER_SEPS = (":", ";", ":@")
QUERY_SEPS = ("==", "==@")
FILE_SEPS = ("=@", ":=@", "@")


def _item(text):
    """(key, separator, value, plain) of a request item: the first separator wins, the longest at that position;
    a backslash escapes the next character. plain is False when the key or value uses an escape or the key the
    nested-JSON path syntax (a[b], a[]), which this module does not assemble. None when there is no separator."""
    i, key, plain = 0, [], True
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            key.append(text[i + 1])
            plain, i = False, i + 2
            continue
        for sep in ITEM_SEPS:
            if text.startswith(sep, i):
                k, v = "".join(key), text[i + len(sep):]
                return k, sep, v, plain and not re.search(r"[\[\]]", k) and "\\" not in v
        key.append(text[i])
        i += 1
    return None


def _httpie(client, argv, out):
    table, name = (HTTPIE, "http") if client == "httpie" else (XH, "xh")
    out.default_config = list(DEFAULT_CONFIG[client])
    s = {"form": False, "raw": None, "ignore_stdin": False, "routes": [], "pos": []}
    for ev in _words(table, argv, STYLE[client]):
        if ev[0] == "pos":
            s["pos"].append(ev[1])
            continue
        if ev[0] != "opt":
            out.bad_word(ev, name)
            continue
        _, opt, value, neg, spelled, _x = ev
        if opt.role == "form":
            s["form"] = not neg
        elif opt.role == "body:raw":
            s["raw"] = None if neg else value
        elif opt.role == "ignore_stdin":
            s["ignore_stdin"] = not neg
        elif opt.role in ("session", "route_override") and not neg:
            s["routes"].append("%s %s" % (spelled, value))
    pos = s["pos"]
    if not pos:
        return
    # httpie and xh read an all-letters first word as the METHOD when a URL follows it.
    if len(pos) >= 2 and METHOD_TOKEN.match(pos[0]):
        word, url, items = pos[0], pos[1], pos[2:]
    else:
        word, url, items = None, pos[0], pos[1:]
    headers, routes, pieces, data, unknown_body = [], list(s["routes"]), [], [], []
    for it in items:
        got = _item(it)
        if got is None:
            out.broken("%s: request item %r has no separator: %s refuses it" % (name, it, name))
            continue
        key, sep, val, plain = got
        if sep in HEADER_SEPS:
            headers.append(it)
            if key.strip().lower() == "host":
                routes.append(it)
        elif sep in QUERY_SEPS:
            if sep == "==@":
                unknown_body.append("%s %s: a query parameter read from a file" % (name, it))
        else:
            pieces.append(it)
            data.append(got)
    stdin = not s["ignore_stdin"] and not data and s["raw"] is None
    if s["raw"] is not None and data:
        out.target("%s refuses --raw with data items" % name)
    if word:
        method = word.upper()
    elif data or s["raw"] is not None:
        method = "POST"
    elif stdin:
        method = None
        out.target("%s with no data item and no --ignore-stdin is a POST when stdin is not a terminal, else a GET"
                   % name)
    else:
        method = "GET"
    if stdin:
        unknown_body.append("%s reads the body from stdin when stdin is not a terminal (--ignore-stdin pins it)" % name)
    body = fields = None
    if s["raw"] is not None:
        pieces.insert(0, s["raw"])
        body, fields = s["raw"], _json_fields(s["raw"])
    elif data:
        for key, sep, val, plain in data:
            if sep in FILE_SEPS:
                unknown_body.append("%s %s%s...: a value or file part read from a file" % (name, key, sep))
            elif not plain:
                unknown_body.append("%s %s%s...: an escaped or nested-JSON item this module does not assemble"
                                    % (name, key, sep))
        keys = [d[0] for d in data]
        if len(set(keys)) != len(keys) and not s["form"]:
            unknown_body.append("%s: a key given twice becomes a JSON array this module does not assemble" % name)
        obj, bad = [], False
        for key, sep, val, plain in data:
            if sep == ":=":
                try:
                    obj.append((key, json.loads(val)))
                except ValueError:
                    out.broken("%s %s:=...: not JSON, %s refuses it" % (name, key, name))
                    bad = True
            elif sep == "=":
                obj.append((key, val))
        if s["form"] or any(d[1] == "@" for d in data):
            typed = [k for k, v in obj if not isinstance(v, str)]
            if typed:
                # A form carries strings: a typed raw-JSON item (force:=true, n:=1) is sent the client's own way
                # (httpie writes str() of it: force=True) or refused, so the parameters are not all known (#349).
                out.why("%s --form %s:=...: a typed JSON value in a form body, which %s renders its own way or "
                        "refuses" % (name, typed[0], name))
                fields = None
            else:
                fields = ["%s=%s" % (k, v) for k, v in obj]
        elif not bad:
            body = json.dumps(dict(obj))
            fields = ["%s=%s" % (k, v if isinstance(v, str) else json.dumps(v, separators=(",", ":")))
                      for k, v in obj]
    out.add(method, [url], pieces, body, fields, unknown_body, routes, headers)


# ---------------------------------------------------------------------------------------------------------------
# gh api <endpoint>

def _gh_api(argv, out):
    s = {"method": None, "fields": [], "input": None, "headers": [], "pos": []}
    for ev in _words(GH_API, argv, "pflag"):
        if ev[0] == "pos":
            s["pos"].append(ev[1])
            continue
        if ev[0] != "opt":
            out.bad_word(ev, "gh api")
            continue
        _, opt, value, _neg, spelled, _x = ev
        if opt.role == "method":
            s["method"] = (value, spelled)
        elif opt.role in ("field", "raw_field"):
            s["fields"].append((opt.role, value, spelled))
        elif opt.role == "body_file":
            s["input"] = value
        elif opt.role == "header":
            s["headers"].append(value)   # Go's client ignores a Host header: gh -H cannot re-target the call
    pos = s["pos"]
    if len(pos) != 1:
        out.target("gh api takes exactly one endpoint; given %d it refuses the command" % len(pos))
    if s["method"]:
        method = _method(s["method"][0], "gh api " + s["method"][1], out)
    else:
        # "adding request parameters will automatically switch the request method to POST" (gh api --help)
        method = "POST" if s["fields"] or s["input"] is not None else "GET"
    unknown_body = []
    for role, val, spelled in s["fields"]:
        key, eq, v = val.partition("=")
        if not eq:
            out.broken("gh api %s %r has no '=': gh refuses it" % (spelled, val))
        elif role == "field" and v.startswith("@"):
            unknown_body.append("gh api %s %s=@...: the value is read from a file or stdin" % (spelled, key))
    if s["input"] is not None:
        unknown_body.append("gh api --input: the body is read from a file or stdin")
    if pos:
        out.add(method, pos, [f[1] for f in s["fields"]], None, [f[1] for f in s["fields"]], unknown_body, [],
                s["headers"])


# ---------------------------------------------------------------------------------------------------------------

def parse(prog, argv):
    """The argv model of one HTTP client call: see the module docstring for the result. Never raises."""
    out = _Out()
    try:
        argv = [w if isinstance(w, str) else str(w) for w in (argv or [])]
        name = (prog or "").replace("\\", "/").rsplit("/", 1)[-1].strip().lower()
        if name.endswith(".exe"):
            name = name[:-4]
        if name == "gh":
            if argv[:1] != ["api"]:
                out.broken("gh %s is not `gh api`" % (argv[0] if argv else "(no subcommand)"))
                return out.result()
            name, argv = "gh api", argv[1:]
        client = CLIENTS.get(name)
        if client is None:
            out.broken("%r is not an HTTP client this module models" % (prog,))
        elif client == "curl":
            _curl(argv, out)
        elif client == "wget":
            _wget(argv, out)
        elif client in ("httpie", "xh"):
            _httpie(client, argv, out)
        else:
            _gh_api(argv, out)
    except Exception as e:   # a defect here must make the call unknown, never quietly safe
        out.broken("pg_http internal error: %s: %s" % (type(e).__name__, e))
    return out.result()


if __name__ == "__main__":
    import sys
    print(json.dumps(parse(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2:]), indent=2))
