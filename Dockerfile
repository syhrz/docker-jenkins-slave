FROM nasqueron/php-cli

MAINTAINER Amal Syahreza <amal.syahreza@gmail.com>

##############################
# Install and configure node #
##############################

RUN curl -sL https://deb.nodesource.com/setup_6.x | bash -

RUN apt-get update \
    && apt-get install -y \
    --no-install-recommends \
    nodejs \
    bzip2 \
    unzip \
    xz-utils
#    && rm -rf /var/lib/apt/lists/*

# Install Jshint and less for build dependencies

RUN npm install -g jshint less

RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

##########################################
# This part install and configure java 8 #
##########################################
RUN echo 'deb http://httpredir.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' $PG_MAJOR > /etc/apt/sources.list.d/pgdg.list

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
	echo '#!/bin/sh'; \
	echo 'set -e'; \
	echo; \
	echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
    } > /usr/local/bin/docker-java-home \
    && chmod +x /usr/local/bin/docker-java-home

ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

ENV JAVA_VERSION 8u91
ENV JAVA_DEBIAN_VERSION 8u91-b14-1~bpo8+1

# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV CA_CERTIFICATES_JAVA_VERSION 20140324

RUN set -x \
    && apt-get update \
    && apt-get install -y \
    openjdk-8-jdk="$JAVA_DEBIAN_VERSION" \
    ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" \
#    && rm -rf /var/lib/apt/lists/* \
    && [ "$JAVA_HOME" = "$(docker-java-home)" ]

# see CA_CERTIFICATES_JAVA_VERSION notes above
RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure

###################
# Config Arcanist #
###################

RUN apt-get update && apt-get install -y \
    mercurial subversion openssh-client locales \
    --no-install-recommends && rm -r /var/lib/apt/lists/* && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

RUN cd /opt && \
    git clone https://github.com/phacility/libphutil.git && \
    git clone https://github.com/phacility/arcanist.git && \
    wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash

RUN cd $HOME && \
    ln -s /opt/arcanist/bin/arc /usr/local/bin/arc && \
    ln -s /opt/config/gitconfig /root/.gitconfig && \
    ln -s /opt/config/arcrc /root/.arcrc

######################
# Install PostgreSQL #
######################

RUN groupadd -r postgres --gid=999 && useradd -r -g postgres --uid=999 postgres

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true
#	&& apt-get purge -y --auto-remove ca-certificates wget

# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
#RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
#	&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

ENV PG_MAJOR 9.5
ENV PG_VERSION 9.5.3-1.pgdg80+1

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' $PG_MAJOR > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update \
	&& apt-get install -y postgresql-common \
	&& sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf \
	&& apt-get install -y \
		postgresql-$PG_MAJOR=$PG_VERSION \
		postgresql-contrib-$PG_MAJOR=$PG_VERSION \
	&& rm -rf /var/lib/apt/lists/*

# make the sample config easier to munge (and "correct by default")
RUN mv -v /usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample /usr/share/postgresql/ \
	&& ln -sv ../postgresql.conf.sample /usr/share/postgresql/$PG_MAJOR/ \
	&& sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres /var/run/postgresql

ENV PATH /usr/lib/postgresql/$PG_MAJOR/bin:$PATH
ENV PGDATA /var/lib/postgresql/data
VOLUME /var/lib/postgresql/data

ENV HOME /home/jenkins

RUN useradd -c "Jenkins user" -d $HOME -m jenkins

RUN curl --create-dirs -sSLo /usr/share/jenkins/slave.jar http://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/2.9/remoting-2.9.jar \
  && chmod 755 /usr/share/jenkins \
  && chmod 644 /usr/share/jenkins/slave.jar

COPY jenkins-slave /usr/local/bin/jenkins-slave

EXPOSE 5432

VOLUME ["/opt/config", "/opt/workspace", "/home/jenkins" ]

VOLUME /home/jenkins

WORKDIR /home/jenkins

RUN echo 'deb http://httpredir.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list

USER jenkins

ENTRYPOINT ["jenkins-slave"]
