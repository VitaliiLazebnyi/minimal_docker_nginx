# ==========================================
# STAGE 1: Builder Environment
# ==========================================
# Pinned by digest; Dependabot (docker) proposes updates and `rake outdated` fails when the tag has moved
# or a newer Ruby/Alpine release exists (see script/outdated_holds.yml).
FROM ruby:4.0.9-alpine3.24@sha256:d0c5befc0864d31c6219321c8d79de2941d1bc31c41505d9c9289c6192c36d60 AS builder

# Every RUN below uses pipes; without pipefail a failing producer would go unnoticed.
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# The newest RubyGems, installed over the one Ruby ships with (checked by `rake outdated`).
ARG RUBYGEMS_VERSION=4.0.23
# Must match the passenger entry of rails_app/Gemfile.lock (checked by `rake outdated`).
ARG PASSENGER_VERSION=6.2.1
# The newest nginx release (mainline; checked by `rake outdated`). The SHA-256 is the one the FreeBSD ports tree
# records for this tarball (www/nginx-devel/distinfo); Passenger itself only carries a checksum for 1.30.6.
ARG NGINX_VERSION=1.31.8
ARG NGINX_SHA256=0652b760b3b772d2ec17b47c2fc15d9a95e6fe35cd5b877eadc1a62d9bc75af1
# The unprivileged account nginx, Passenger and the application run as.
ARG APP_UID=10001

# 1. Install toolchain & dependencies for Ruby, Passenger and nginx compilation
RUN apk add --no-cache gcc g++ make linux-headers patch musl-dev coreutils xz \
    tzdata sqlite-dev yaml-dev pcre2-dev curl-dev libxml2-dev libxslt-dev curl bash \
    openssl-dev zlib-dev libffi-dev readline-dev gdbm-dev ncurses-dev \
    logrotate perl tar procps && \
    adduser -D -H -h /home/app -s /sbin/nologin -u "${APP_UID}" app

# 2. Rails Application Setup
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_FROZEN="true"

ENV OPTIMIZATION_FLAGS="-Ofast -ffast-math -march=native -mtune=native -flto -fomit-frame-pointer -pipe"
ENV CFLAGS="${OPTIMIZATION_FLAGS}" \
    CXXFLAGS="${OPTIMIZATION_FLAGS}" \
    RUBY_CFLAGS="${OPTIMIZATION_FLAGS}" \
    RUBY_CXXFLAGS="${OPTIMIZATION_FLAGS}"

# 2.5: Re-compile the Ruby VM with the optimization flags, from the exact source tarball of the base image
# (RUBY_DOWNLOAD_URL and RUBY_DOWNLOAD_SHA256 are set by the official ruby image), verified before use.
WORKDIR /usr/src/ruby
RUN curl --fail --silent --show-error --location --output ruby.tar.xz "${RUBY_DOWNLOAD_URL}" && \
    echo "${RUBY_DOWNLOAD_SHA256}  ruby.tar.xz" | sha256sum -c - && \
    tar -xJf ruby.tar.xz --strip-components=1 && \
    rm ruby.tar.xz && \
    ./configure --disable-install-doc --enable-shared && \
    make -j"$(nproc)" install && \
    gem update --system "${RUBYGEMS_VERSION}" --no-document
WORKDIR /
RUN rm -rf /usr/src/ruby

COPY rails_app /app
WORKDIR /app
RUN bundle config set --global build.nokogiri "--with-cflags='${OPTIMIZATION_FLAGS}' --with-cxxflags='${OPTIMIZATION_FLAGS}'" && \
    bundle config set --global build.sqlite3 "--with-cflags='${OPTIMIZATION_FLAGS}' --with-cxxflags='${OPTIMIZATION_FLAGS}'" && \
    bundle install && rm -rf /usr/local/bundle/cache /app/vendor && \
    mkdir -p /app/tmp /app/log /app/storage && \
    chown -R app:app /app/tmp /app/log /app/storage

# 3. Build Passenger & Nginx from the verified nginx source tarball
WORKDIR /usr/src/nginx
RUN curl --fail --silent --show-error --location --output nginx.tar.gz \
      "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    echo "${NGINX_SHA256}  nginx.tar.gz" | sha256sum -c - && \
    tar -xzf nginx.tar.gz --strip-components=1 && \
    rm nginx.tar.gz && \
    gem install passenger --version "${PASSENGER_VERSION}" --no-document && \
    passenger-install-nginx-module --auto --nginx-source-dir=/usr/src/nginx --prefix=/opt/nginx --languages ruby \
      --extra-configure-flags="--with-cc-opt='${OPTIMIZATION_FLAGS}' --with-ld-opt='-Wl,-flto'"
WORKDIR /app
RUN rm -rf /usr/src/nginx

# 4. Configuration Layer
COPY docker_config/nginx.conf.template /tmp/nginx.conf.template
COPY docker_config/logrotate.conf /etc/logrotate.conf
COPY docker_config/entrypoint.sh /bin/entrypoint.sh
RUN PASSENGER_ROOT=$(passenger-config --root) && \
    sed "s|REPLACE_ME_PASSENGER_ROOT|$PASSENGER_ROOT|g" /tmp/nginx.conf.template > /opt/nginx/conf/nginx.conf && \
    chmod 755 /bin/entrypoint.sh && chmod 644 /etc/logrotate.conf /opt/nginx/conf/nginx.conf && \
    # Runtime directories: every log under /var/logs (REQ-LOG-001), owned by the unprivileged account.
    # The account's home directory is writable too (Bundler keeps its per-user settings there).
    mkdir -p /my_runtime/var/logs/nginx /my_runtime/var/logs/passenger /my_runtime/tmp/nginx /my_runtime/tmp/passenger \
      /my_runtime/home/app && \
    chown -R app:app /my_runtime/var/logs /my_runtime/tmp/nginx /my_runtime/tmp/passenger /my_runtime/home/app && \
    chmod 1777 /my_runtime/tmp

# 5. Hyper-Minimization Sequence (DOCKER_MINIMIZATION.md)
# strip fails on files that are not ELF objects (linker scripts named *.so*); those are left as they are.
RUN find /usr/local -type f -name '*.so*' -exec strip --strip-unneeded {} + || true && \
    strip --strip-unneeded /usr/local/bin/ruby /opt/nginx/sbin/nginx && \
    # Purge C-Compiler Metadata directories
    rm -rf /usr/local/lib/pkgconfig /usr/local/include/ruby-* && \
    # Nuke Default Development Gems built into Ruby
    for gem in minitest test-unit power_assert rbs typeprof debug irb reline syntax_suggest error_highlight rdoc racc; do \
        rm -rf /usr/local/lib/ruby/gems/*/gems/"${gem}"-* ; \
        rm -f /usr/local/lib/ruby/gems/*/specifications/"${gem}"-*.gemspec ; \
        rm -f /usr/local/lib/ruby/gems/*/specifications/default/"${gem}"-*.gemspec ; \
    done && \
    # The "Dirty Secret" of RubyGems (C/C++ Compiler Trash)
    find /usr/local/lib/ruby/gems/ /usr/local/bundle/ /opt/nginx/ -type f \( -name "*.c" -o -name "*.h" -o -name "*.o" -o -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" -o -name "*.cxx" -o -name "Makefile" \) -delete

# The "Absolute Minimum" Document/Test Purge (User Request)
RUN find /usr/local/bundle/ruby/*/gems/ -maxdepth 2 -type d \( -name test -o -name tests -o -name spec -o -name features -o -name benchmark -o -name examples -o -name doc -o -name docs -o -name sample -o -name samples -o -name man -o -name manual -o -name templates \) -exec rm -rf {} + || true && \
    find /usr/local/bundle/gems/ -maxdepth 2 -type d \( -name test -o -name tests -o -name spec -o -name features -o -name benchmark -o -name examples -o -name doc -o -name docs -o -name sample -o -name samples -o -name man -o -name manual -o -name templates \) -exec rm -rf {} + || true && \
    find /usr/local/lib/ruby/ -maxdepth 3 -type d \( -name test -o -name tests -o -name spec -o -name features -o -name benchmark -o -name examples -o -name doc -o -name docs -o -name sample -o -name samples -o -name man -o -name manual -o -name templates \) -exec rm -rf {} + || true && \
    find /usr/local/lib/ruby/gems/*/gems/ -maxdepth 2 -type d \( -name test -o -name tests -o -name spec -o -name features -o -name benchmark -o -name examples -o -name doc -o -name docs -o -name sample -o -name samples -o -name man -o -name manual \) -exec rm -rf {} + || true && \
    find /usr/local -type d -name "generators" -exec rm -rf {} + || true && \
    find /usr/local -name "*.a" -delete || true && \
    find /usr/local -name "*.la" -delete || true && \
    find /usr/local -type d -name "include" -exec rm -rf {} + || true && \
    find /usr/local -type d -name ".github" -exec rm -rf {} + || true && \
    rm -rf /opt/nginx/html /opt/nginx/logs && \
    rm -f /opt/nginx/conf/*.default /opt/nginx/conf/fastcgi* /opt/nginx/conf/scgi* /opt/nginx/conf/uwsgi* /opt/nginx/conf/koi* /opt/nginx/conf/win* && \
    ln -s /var/logs/nginx /opt/nginx/logs && \
    for ext in "*.md" "*.txt" "*.log" "README*" "*LICENSE*" "*GPL*" "COPYING*" "BSDL" "CHANGELOG*" "CHANGES*" "CONTRIBUTING*" "CONTRIBUTORS*" "Rakefile*" "Makefile*" "BSDmakefile" "mkmf.log" "USAGE*" "TODO*" "THANKS*" ".document" ".gitignore" "Gemfile" "*.java" ".travis.yml" ".yardopts" "*.out"; do \
        find /usr/local/bundle -iname "$ext" -exec rm -f {} + || true; \
        find /usr/local/lib -iname "$ext" -exec rm -f {} + || true; \
    done && \
    rm -rf /usr/local/bundle/ruby/*/cache \
           /usr/local/bundle/cache \
           /usr/local/lib/ruby/gems/*/cache \
           /usr/local/bundle/gems/passenger-*/resources/templates/apache2 \
           /usr/local/bundle/gems/passenger-*/resources/templates/standalone \
           /usr/local/bundle/gems/passenger-*/resources/templates/installer_common \
           /usr/local/bundle/gems/passenger-*/resources/templates/config \
           /usr/local/bundle/gems/passenger-*/resources/templates/nginx \
           /usr/local/bundle/ruby/*/gems/passenger-*/resources/templates/apache2 \
           /usr/local/bundle/ruby/*/gems/passenger-*/resources/templates/standalone \
           /usr/local/bundle/ruby/*/gems/passenger-*/resources/templates/installer_common \
           /usr/local/bundle/ruby/*/gems/passenger-*/resources/templates/config \
           /usr/local/bundle/ruby/*/gems/passenger-*/resources/templates/nginx \
           /usr/local/bundle/gems/passenger-*/build \
           /usr/local/bundle/gems/passenger-*/dev \
           /usr/local/bundle/gems/passenger-*/configure \
           /usr/local/bundle/gems/passenger-*/package.json \
           /usr/local/bundle/gems/passenger-*/images \
           /usr/local/bundle/gems/passenger-*/resources/update_check_client_cert.p12 \
           /usr/local/bundle/ruby/*/gems/passenger-*/build \
           /usr/local/bundle/ruby/*/gems/passenger-*/dev \
           /usr/local/bundle/ruby/*/gems/passenger-*/configure \
           /usr/local/bundle/ruby/*/gems/passenger-*/package.json \
           /usr/local/bundle/ruby/*/gems/passenger-*/images \
           /usr/local/bundle/ruby/*/gems/passenger-*/resources/update_check_client_cert.p12 \
           /usr/local/bundle/ruby/*/gems/rdoc-* \
           /usr/local/lib/ruby/gems/*/gems/rdoc-* \
           /usr/local/bundle/ruby/*/gems/irb-* \
           /usr/local/lib/ruby/gems/*/gems/irb-* \
           /usr/local/bundle/ruby/*/gems/typeprof-* \
           /usr/local/lib/ruby/gems/*/gems/typeprof-* \
           /usr/local/bundle/ruby/*/gems/rbs-* \
           /usr/local/lib/ruby/gems/*/gems/rbs-* \
           /usr/local/bundle/ruby/*/gems/syntax_suggest-* \
           /usr/local/lib/ruby/gems/*/gems/syntax_suggest-* \
           /usr/local/bundle/ruby/*/gems/test-unit-* \
           /usr/local/lib/ruby/gems/*/gems/test-unit-* \
           /usr/local/bundle/ruby/*/gems/minitest-* \
           /usr/local/lib/ruby/gems/*/gems/minitest-* \
           /usr/local/bundle/ruby/*/gems/rdbg-* \
           /usr/local/lib/ruby/gems/*/gems/rdbg-* \
           /usr/local/bundle/ruby/*/gems/debug-* \
           /usr/local/lib/ruby/gems/*/gems/debug-* \
           /usr/local/bundle/ruby/*/specifications/rdbg-*.gemspec \
           /usr/local/bundle/bin/passenger* \
           /usr/local/bundle/ruby/*/gems/passenger-* \
           /usr/local/bundle/ruby/*/doc \
           /usr/local/lib/ruby/gems/*/doc \
           /usr/local/share \
           /app/.git /app/coverage /app/tmp/* /app/log/* /app/.rspec /app/test /app/spec && \
    find /usr/local/bundle/ -type d \( -name "cxx_supportlib" -o -name "ruby_native_extension" -o -name "apache2_module" -o -name "nodejs_supportlib" -o -name "nginx_module" -o -name "schema_printer" -o -name "agent" -o -name "download_cache" -o -name "libev" -o -name "libuv" \) -exec rm -rf {} + || true

# 6. Paranoid Hyper-Minimization (The "Scratch Copy" Dependencies)
# Extract exact physical paths of all dynamic OS libraries for passenger, ruby, nginx, and required utils
# (ldd prints nothing for files that are not dynamic ELF objects).
RUN mkdir /my_dependencies && \
    find /usr/local /opt/nginx /bin/busybox /bin/ps /usr/sbin/logrotate -type f \( -executable -o -name "*.so" \) \
      -exec sh -c 'for file; do ldd "$file" 2>/dev/null || true; done' sh {} + \
      | awk '{print $3}' | grep "^/" | sort -u | xargs -r -I '{}' cp '{}' /my_dependencies/

# Symbolic links to busybox for the shell tools the entrypoint, logrotate, Passenger and the HEALTHCHECK use.
# /lib/ld-musl-*.so.1 is needed to execute any binary; it is copied explicitly.
RUN mkdir -p /my_bin /my_sbin /my_lib /my_usr_bin && \
    cp /bin/busybox /my_bin/ && \
    for cmd in sh rm mv gzip mkdir chown chmod ls kill sleep cat echo date false true grep id uname env wget; do \
        ln -s /bin/busybox "/my_bin/$cmd"; \
    done && \
    cp /bin/ps /my_bin/ps && \
    cp /usr/sbin/logrotate /my_sbin/ && \
    cp /lib/ld-musl-*.so.1 /my_lib/

# ==========================================
# STAGE 2: Ultra-Minimal Production Image
# ==========================================
FROM scratch

ENV TZ=UTC \
    RAILS_ENV=production \
    BUNDLE_PATH="/usr/local/bundle" \
    GEM_HOME="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    DATABASE_URL="sqlite3:storage/production.sqlite3?max_connections=5&timeout=5000" \
    PATH="/usr/local/bin:/opt/nginx/sbin:/bin:/sbin:/usr/bin:/usr/sbin"

COPY --from=builder /my_dependencies /lib
COPY --from=builder /my_dependencies /usr/lib
COPY --from=builder /my_lib/ /lib/
COPY --from=builder /my_bin /bin
COPY --from=builder /my_sbin /usr/sbin
COPY --from=builder /my_usr_bin /usr/bin
# Core system properties Passenger relies upon (it looks the running account up by uid)
COPY --from=builder /etc/passwd /etc/group /etc/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /usr/share/zoneinfo/UTC /etc/localtime

# Ruby Environment
COPY --from=builder /usr/local /usr/local
COPY --from=builder /opt/nginx /opt/nginx

COPY --from=builder /app /app
COPY --from=builder /etc/logrotate.conf /etc/logrotate.conf
COPY --from=builder /bin/entrypoint.sh /bin/entrypoint.sh
# /var/logs/{nginx,passenger}, /tmp (sticky, world-writable) and its nginx/Passenger directories
COPY --from=builder /my_runtime/ /

WORKDIR /app

# nginx, Passenger and the application run unprivileged. Port 80 stays bindable because Docker sets
# net.ipv4.ip_unprivileged_port_start=0 in every container network namespace (see README.md).
USER 10001:10001

EXPOSE 80

# 127.0.0.1, not localhost: nginx listens on IPv4, and BusyBox wget does not fall back to IPv4 when
# localhost resolves to ::1 first.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/bin/sh", "-c", "env /bin/busybox wget -q -O - http://127.0.0.1/health | /bin/busybox grep OK || exit 1"]

ENTRYPOINT ["/bin/sh", "/bin/entrypoint.sh"]
