# ==========================================
# STAGE 1: Builder Environment
# ==========================================
FROM ruby:4.0.2-alpine AS builder

# 1. Install toolchain & dependencies for passenger compilation
RUN apk add --no-cache gcc g++ make linux-headers rust cargo patch musl-dev \
    tzdata sqlite-dev yaml-dev pcre-dev curl-dev libxml2-dev libxslt-dev curl bash \
    logrotate perl tar procps procps

# 2. Rails Application Setup
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

COPY rails_app /app
RUN chown -R nobody:nobody /app
WORKDIR /app

ENV OPTIMIZATION_FLAGS="-Ofast -ffast-math -march=native -mtune=native -flto -fomit-frame-pointer -pipe"
ENV CFLAGS="${OPTIMIZATION_FLAGS}"
ENV CXXFLAGS="${OPTIMIZATION_FLAGS}"
ENV RUBY_CFLAGS="${OPTIMIZATION_FLAGS}"
ENV RUBY_CXXFLAGS="${OPTIMIZATION_FLAGS}"

# 2.5: Physically Re-compile the Ruby Virtual Machine Engine iteratively over the generic binary
RUN apk add --no-cache curl tar build-base linux-headers coreutils yaml-dev openssl-dev zlib-dev libffi-dev readline-dev gdbm-dev ncurses-dev && \
    curl -sL https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.2.tar.gz | tar -xz && \
    cd ruby-4.0.2 && \
    ./configure --disable-install-doc --enable-shared && \
    make -j$(nproc) install && \
    cd .. && rm -rf ruby-4.0.2

RUN bundle config set --global build.nokogiri "--with-cflags='${OPTIMIZATION_FLAGS}' --with-cxxflags='${OPTIMIZATION_FLAGS}'" && \
    bundle config set --global build.sqlite3 "--with-cflags='${OPTIMIZATION_FLAGS}' --with-cxxflags='${OPTIMIZATION_FLAGS}'" && \
    bundle install && rm -rf /usr/local/bundle/cache /app/vendor

# 3. Build Passenger & Nginx
RUN gem install passenger --no-document
RUN passenger-install-nginx-module --auto --auto-download --prefix=/opt/nginx --languages ruby --extra-configure-flags="--with-cc-opt='${OPTIMIZATION_FLAGS}' --with-ld-opt='-Wl,-flto'"

# 4. Configuration Layer
COPY docker_config/nginx.conf.template /tmp/nginx.conf.template
RUN PASSENGER_ROOT=$(passenger-config --root) && \
    sed "s|REPLACE_ME_PASSENGER_ROOT|$PASSENGER_ROOT|g" /tmp/nginx.conf.template > /opt/nginx/conf/nginx.conf

COPY docker_config/logrotate.conf /etc/logrotate.conf
COPY docker_config/entrypoint.sh /bin/entrypoint.sh
RUN chmod +x /bin/entrypoint.sh && chmod 644 /etc/logrotate.conf

# 5. Hyper-Minimization Sequence (DOCKER_MINIMIZATION.md)
RUN find /usr/local -type f -name '*.so*' -exec strip --strip-unneeded {} + && \
    strip --strip-unneeded /usr/local/bin/ruby || true && \
    strip --strip-unneeded /opt/nginx/sbin/nginx || true

# Purge C-Compiler Metadata directories
RUN rm -rf /usr/local/lib/pkgconfig /usr/local/include/ruby-*

# Nuke Default Development Gems built into Ruby
RUN for gem in minitest test-unit power_assert rbs typeprof debug irb reline syntax_suggest error_highlight rdoc racc; do \
        rm -rf /usr/local/lib/ruby/gems/*/gems/${gem}-* ; \
        rm -f /usr/local/lib/ruby/gems/*/specifications/${gem}-*.gemspec ; \
        rm -f /usr/local/lib/ruby/gems/*/specifications/default/${gem}-*.gemspec ; \
    done

# The "Dirty Secret" of RubyGems (C/C++ Compiler Trash)
RUN find /usr/local/lib/ruby/gems/ /usr/local/bundle/ /opt/nginx/ -type f \( -name "*.c" -o -name "*.h" -o -name "*.o" -o -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" -o -name "*.cxx" -o -name "Makefile" \) -delete

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
    rm -rf /opt/nginx/html /opt/nginx/logs || true && \
    rm -f /opt/nginx/conf/*.default /opt/nginx/conf/fastcgi* /opt/nginx/conf/scgi* /opt/nginx/conf/uwsgi* /opt/nginx/conf/koi* /opt/nginx/conf/win* || true && \
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
           /app/.git /app/coverage /app/tmp/* /app/log/* /app/.rspec /app/test /app/spec || true && \
    find /usr/local/bundle/ -type d \( -name "cxx_supportlib" -o -name "ruby_native_extension" -o -name "apache2_module" -o -name "nodejs_supportlib" -o -name "nginx_module" -o -name "schema_printer" -o -name "agent" -o -name "download_cache" -o -name "libev" -o -name "libuv" \) -exec rm -rf {} + || true

# 6. Paranoid Hyper-Minimization (The "Scratch Copy" Dependencies)
# Extract exact physical paths of all dynamic OS libraries for passenger, ruby, nginx, and required utils
# We also include dynamic libraries loaded by ld-musl, which ldd surfaces
RUN mkdir /my_dependencies && \
    for lib in $(find /usr/local /opt/nginx /bin/busybox /bin/ps /usr/sbin/logrotate -type f \( -executable -o -name "*.so" \)); do \
        ldd $lib 2>/dev/null | awk '{print $3}' | grep "^/"; \
    done | sort -u | xargs -I '{}' cp '{}' /my_dependencies/ || true

# Create symbolic links to busybox for critical scratch shell tools
# We also need /lib/ld-musl-aarch64.so.1 (or x86_64) to execute binaries; it's a symlink in Alpine usually.
# LDD resolves it to absolute physical object. Let's explicitly copy /lib/ld-musl-*.so.1
RUN mkdir -p /my_bin /my_sbin /my_lib /my_usr_bin && \
    cp /bin/busybox /my_bin/ && \
    for cmd in sh rm mv gzip mkdir chown chmod ls kill sleep cat echo date false true grep id uname env wget; do \
        ln -s /bin/busybox /my_bin/$cmd || true; \
    done && \
    ln -s /bin/busybox /my_sbin/crond || true && \
    cp /bin/ps /my_bin/ps || true && \
    cp /usr/sbin/logrotate /my_sbin/ && \
    cp /lib/ld-musl-*.so.1 /my_lib/ || echo "ld-musl copy failed"

# ==========================================
# STAGE 2: Ultra-Minimal Production Image
# ==========================================
FROM scratch

ENV TZ=UTC \
    RAILS_ENV=production \
    BUNDLE_PATH="/usr/local/bundle" \
    GEM_HOME="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    PATH="/usr/local/bin:/opt/nginx/sbin:/bin:/sbin:/usr/bin:/usr/sbin"

# Important missing musl loader symlink workaround if placed in /lib
# We just copy the folders we built directly.
COPY --from=builder /my_dependencies /lib
COPY --from=builder /my_dependencies /usr/lib
COPY --from=builder /my_lib/ /lib/
COPY --from=builder /my_bin /bin
COPY --from=builder /my_sbin /usr/sbin
COPY --from=builder /my_usr_bin /usr/bin
COPY --from=builder /etc/passwd /etc/group /etc/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# 2. Ruby Environment
COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /opt/nginx /opt/nginx

COPY --from=builder /app /app
COPY --from=builder /etc/logrotate.conf /etc/logrotate.conf
COPY --from=builder /bin/entrypoint.sh /bin/entrypoint.sh
COPY --from=builder /usr/share/zoneinfo/UTC /etc/localtime

# Core system properties passenger agent relies upon
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Working directory
WORKDIR /app

# Expose port
EXPOSE 80

# The Docker HEALTHCHECK instruction
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/bin/sh", "-c", "env /bin/busybox wget -q -O - http://localhost/health | /bin/busybox grep OK || exit 1"]

# The process execution sequence
ENTRYPOINT ["/bin/sh", "/bin/entrypoint.sh"]
