FROM alpine:latest
ENV AKTUALIZR_SRCREV 2020.10+fio
WORKDIR /root/

RUN apk add --no-cache cmake git g++ make curl-dev libarchive-dev libsodium-dev dpkg-dev doxygen graphviz sqlite-dev glib-dev autoconf automake libtool python3 boost-dev ninja \
	&& git clone https://github.com/vlm/asn1c \
	&& cd asn1c \
	&& autoreconf -iv \
	&& ./configure \
	&& make -j`getconf _NPROCESSORS_ONLN` install \
	&& cd ../ \
	&& git clone https://github.com/foundriesio/aktualizr.git \
	&& cd aktualizr \
	&& git checkout $AKTUALIZR_SRCREV \
	&& git submodule update --init --recursive \
	&& mkdir build-git \
	&& cd build-git \
	&& sed -i '/GLOB_PERIOD/a #define GLOB_TILDE 4096' /usr/include/glob.h \
	&& cmake -GNinja -DWARNING_AS_ERROR=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SOTA_TOOLS=ON .. \
	&& ninja src/sota_tools/install

# download and extract OE utilities
RUN cd /root/ \
  && mkdir oe \
  && wget https://github.com/openembedded/openembedded-core/archive/2020-04.1-dunfell.tar.gz -O oe.tar.gz \
  && tar -xf oe.tar.gz --strip-components=1 -C oe \
  && rm oe.tar.gz

RUN apk add patch
COPY 0001-wic-Adjust-cmd-line-format-to-debugfs-1.45.6.patch /root/oe
RUN cd /root/oe \
  && patch scripts/lib/wic/engine.py 0001-wic-Adjust-cmd-line-format-to-debugfs-1.45.6.patch

RUN apk add python3 py3-pip libffi-dev make openssl-dev gcc libc-dev python3-dev
RUN pip3 install docker-compose==1.27 expandvars==0.6.5

## Stage 2
FROM docker:dind
WORKDIR /root/

RUN apk add --no-cache bash glib libarchive libcurl libsodium nss openjdk8-jre-base ostree python3 boost-program_options boost-log boost-filesystem boost-log_setup parted sgdisk git
RUN wget -O /tmp/docker-app.tgz  https://github.com/docker/app/releases/download/v0.9.0-beta1/docker-app-linux.tar.gz \
	&& tar xf "/tmp/docker-app.tgz" -C /tmp/ \
	&& mkdir -p /usr/lib/docker/cli-plugins \
	&& mv "/tmp/docker-app-plugin-linux" /usr/lib/docker/cli-plugins/docker-app \
	&& rm /tmp/docker*
ENV DOCKER_CLI_EXPERIMENTAL=enabled
COPY ota-publish.sh /usr/bin/ota-publish
COPY ota-dockerapp.py /usr/bin/ota-dockerapp
COPY --from=0 /usr/lib/python3.8/site-packages /usr/lib/python3.8/site-packages
COPY --from=0 /usr/bin/docker-compose /usr/bin/
COPY --from=0 /root/aktualizr/build-git/src/sota_tools/garage-check /usr/bin/
COPY --from=0 /root/aktualizr/build-git/src/sota_tools/garage-deploy /usr/bin/
COPY --from=0 /root/aktualizr/build-git/src/sota_tools/garage-push /usr/bin/
COPY --from=0 /root/aktualizr/build-git/src/sota_tools/garage-sign/bin/garage-sign /usr/bin/
COPY --from=0 /root/aktualizr/build-git/src/sota_tools/garage-sign/lib/ /usr/lib/
COPY --from=0 /root/aktualizr/build-git/src/sota_tools/libsota_tools.so /usr/lib/

# install OE core utilities, WIC utility is located here /usr/bin/oe/scripts/wic
COPY --from=0 /root/oe /usr/bin/oe

CMD bash
ENTRYPOINT []
