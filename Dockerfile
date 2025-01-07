# Base taken from https://github.com/docker-library/mongo/blob/master/8.0/Dockerfile
FROM ubuntu:noble-20241118.1

ARG MONGO_VERSION
ARG MONGO_MAJOR="${MONGO_VERSION%.*}" \
	MONGO_PGPKEY_FINGERPRINT=4B0752C1BCA238C0B4EE14DC41DE058A4E7DCA05 \
	MONGO_PACKAGE=mongodb-org \
	# MONGO_PACKAGE=mongodb-enterprise \
	MONGO_REPO=repo.mongodb.org \
	# MONGO_REPO=repo.mongodb.com \
	\
	JSYAML_VERSION=3.13.1 \
	JSYAML_CHECKSUM=662e32319bdd378e91f67578e56a34954b0a2e33aca11d70ab9f4826af24b941
	# \
	# REPLACED WITH USER COMMAND
	# GOSU_VERSION=1.17 \
	# GOSU_PGPKEY_FINGERPRINT=B42F6819007F00F88E364FD4036A9C25BF357DD4

# Dependencies
RUN set -eux \
	\
	# Add user/group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
	&& groupadd --gid 999 --system mongodb \
	&& useradd --uid 999 --system --gid mongodb --home-dir /data/db mongodb \
	&& mkdir -p /data/db /data/configdb \
	&& chown -R mongodb:mongodb /data/db /data/configdb \
	\
	# Adding required packages
	&& apt-get update && apt-get install -y --no-install-recommends \
		# Will be in the final image - pinning version
		ca-certificates=20240203 \
		numactl=2.0.18-1build1 \
		# Not in the final image - no pinning required
		gnupg \
		wget \
	\
	# js-yaml for parsing mongod's YAML config files (https://github.com/nodeca/js-yaml/releases)
	&& mkdir -p /opt/js-yaml/ \
	&& wget -O /opt/js-yaml/js-yaml.tgz https://registry.npmjs.org/js-yaml/-/js-yaml-${JSYAML_VERSION}.tgz \
	&& echo "$JSYAML_CHECKSUM */opt/js-yaml/js-yaml.tgz" | sha256sum -c - \
	&& tar -xz --strip-components=1 -f /opt/js-yaml/js-yaml.tgz -C /opt/js-yaml package/dist/js-yaml.js package/package.json \
	&& ln -s /opt/js-yaml/dist/js-yaml.js /js-yaml.js \
	# Cleaning
	&& rm -rf /opt/js-yaml/js-yaml.tgz /var/lib/apt/lists/* /tmp/* /var/tmp/*
	# \
	# REPLACED WITH USER COMMAND
	# gosu for easy step-down from root (https://github.com/tianon/gosu/releases)
	# && wget -O /usr/local/bin/gosu https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64 \
	# && wget -O /usr/local/bin/gosu.asc https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64.asc \
	# && export GNUPGHOME="$(mktemp -d)" \
	# && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys ${GOSU_PGPKEY_FINGERPRINT} \
	# && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	# && gpgconf --kill all \
	# && chmod +x /usr/local/bin/gosu \
	# && gosu --version \
	# && gosu nobody true \
	# && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
	

# Mongo
RUN set -eux \
	&& mkdir /docker-entrypoint-initdb.d \
	# PGP Keys
	&& export GNUPGHOME="$(mktemp -d)" \
	&& wget -O KEYS https://pgp.mongodb.com/server-${MONGO_MAJOR}.asc \
	&& gpg --batch --import KEYS \
	&& mkdir -p /etc/apt/keyrings \
	&& gpg --batch --export --armor ${MONGO_PGPKEY_FINGERPRINT} > /etc/apt/keyrings/mongodb.asc \
	&& gpgconf --kill all \
	# Installation
	&& echo "deb [ signed-by=/etc/apt/keyrings/mongodb.asc ] http://$MONGO_REPO/apt/ubuntu noble/${MONGO_PACKAGE}/$MONGO_MAJOR multiverse" \
		| tee "/etc/apt/sources.list.d/${MONGO_PACKAGE}.list" \
	&& apt-get update && apt-get install -y \
		${MONGO_PACKAGE}=$MONGO_VERSION \
		${MONGO_PACKAGE}-server=$MONGO_VERSION \
		${MONGO_PACKAGE}-shell=$MONGO_VERSION \
		${MONGO_PACKAGE}-mongos=$MONGO_VERSION \
		${MONGO_PACKAGE}-tools=$MONGO_VERSION \
		${MONGO_PACKAGE}-database=$MONGO_VERSION \
		${MONGO_PACKAGE}-database-tools-extra=$MONGO_VERSION \
	&& mv /etc/mongod.conf /etc/mongod.conf.orig \
	# Cleaning
	&& rm -rf "$GNUPGHOME" KEYS /var/lib/mongodb /var/lib/apt/lists/* /tmp/* /var/tmp/* 

# Cleaning
RUN apt-get purge -y --auto-remove --allow-remove-essential \
    wget \
    gnupg \
    perl-base \
	hostname \
	sed \
	grep \
	e2fsprogs \
	logsave \
	login \
	util-linux \
	sysvinit-utils \
	sensible-utils \
	findutils \
	bsdutils \
	apt \
	gpgv \
	gzip

VOLUME /data/db /data/configdb

# ensure that if running as custom user that "mongosh" has a valid "HOME"
# https://github.com/docker-library/mongo/issues/524
ENV HOME=/data/db

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

EXPOSE 27017

USER mongodb
CMD ["mongod"]