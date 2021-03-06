# Based on - https://raw.githubusercontent.com/stilliard/docker-pure-ftpd/hardened/Dockerfile

#Stage 1 : builder debian image
FROM debian:stretch as builder

# properly setup debian sources
ENV DEBIAN_FRONTEND noninteractive
RUN echo "deb http://http.debian.net/debian stretch main\n\
deb-src http://http.debian.net/debian stretch main\n\
deb http://http.debian.net/debian stretch-updates main\n\
deb-src http://http.debian.net/debian stretch-updates main\n\
deb http://security.debian.org stretch/updates main\n\
deb-src http://security.debian.org stretch/updates main\n\
" > /etc/apt/sources.list

# install package building helpers
# rsyslog for logging (ref https://github.com/stilliard/docker-pure-ftpd/issues/17)
RUN apt-get -y update && \
	apt-get -y --force-yes --fix-missing install dpkg-dev debhelper &&\
	apt-get -y build-dep pure-ftpd
	

# Build from source - we need to remove the need for CAP_SYS_NICE and CAP_DAC_READ_SEARCH
RUN mkdir /tmp/pure-ftpd/ && \
	cd /tmp/pure-ftpd/ && \
	apt-get source pure-ftpd && \
	cd pure-ftpd-* && \
	./configure --with-tls | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory' && \
	sed -i '/CAP_SYS_NICE,/d; /CAP_DAC_READ_SEARCH/d; s/CAP_SYS_CHROOT,/CAP_SYS_CHROOT/;' src/caps_p.h && \
	dpkg-buildpackage -b -uc | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory'


#Stage 2 : actual pure-ftpd image
FROM debian:stretch

# feel free to change this ;)
LABEL maintainer "Scott Vance <logic@newbaselogic.com>"

# install dependencies
# FIXME : libcap2 is not a dependency anymore. .deb could be fixed to avoid asking this dependency
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && \
	apt-get  --no-install-recommends --yes install \
	openbsd-inetd \
	rsyslog \
	lsb-base \
	libc6 \
	libcap2 \
	libpam0g \
	libssl1.1 \
	openssl \
	s3fs

COPY --from=builder /tmp/pure-ftpd/*.deb /tmp/pure-ftpd/

# install the new deb files
RUN dpkg -i /tmp/pure-ftpd/pure-ftpd-common*.deb &&\
	dpkg -i /tmp/pure-ftpd/pure-ftpd_*.deb && \
	rm -Rf /tmp/pure-ftpd 

# Prevent pure-ftpd upgrading
RUN apt-mark hold pure-ftpd pure-ftpd-common

# setup ftpgroup and ftpuser
RUN groupadd ftpgroup &&\
	useradd -g ftpgroup -d /home/ftpusers -s /dev/null ftpuser

# configure rsyslog logging
RUN echo "" >> /etc/rsyslog.conf && \
	echo "#PureFTP Custom Logging" >> /etc/rsyslog.conf && \
	echo "ftp.* /var/log/pure-ftpd/pureftpd.log" >> /etc/rsyslog.conf && \
	echo "Updated /etc/rsyslog.conf with /var/log/pure-ftpd/pureftpd.log"

# setup run/init file
COPY run.sh /ftps3/run.sh
RUN chmod u+x /ftps3/run.sh

COPY ftps3-add-user.sh /usr/local/bin/ftps3-add-user.sh
RUN chmod +x /usr/local/bin/ftps3-add-user.sh

# Copy fuse config.
COPY fuse.conf /etc/fuse.conf

# default publichost, you'll need to set this for passive support
ENV PUBLICHOST localhost
ENV PURE_PASSWDFILE /home/ftpusers/ftp-config/pureftpd.passwd
ENV S3_MOUNT_PATH /home/ftpusers
ENV S3_USERS_DIR /home/ftpusers/ftp

# startup
CMD /ftps3/run.sh -l puredb:/etc/pure-ftpd/pureftpd.pdb -E -j -R -P $PUBLICHOST -s -A -j -Z -H -4 -E -R -G -X -x

EXPOSE 21 30000-30009
