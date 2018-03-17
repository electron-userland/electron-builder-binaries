FROM buildpack-deps:xenial-curl

RUN apt-get -qq update && apt-get -qq dist-upgrade && apt-get install -qq libssl-dev libcurl4-openssl-dev libgsf-1-dev autoconf build-essential unzip libtool

## Download and install osslsigncode
#RUN curl -L "http://downloads.sourceforge.net/project/osslsigncode/osslsigncode/osslsigncode-1.7.1.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fosslsigncode%2Ffiles%2Fosslsigncode%2F&ts=1413463046&use_mirror=optimate" | tar -xz
#WORKDIR osslsigncode-1.7.1
#RUN ./configure && make && make install

RUN curl -L https://github.com/electron-userland/electron-builder-binaries/files/1821437/osslsigncode-osslsigncode-e72a1937d1a13e87074e4584f012f13e03fc1d64.zip -o f.zip && unzip f.zip && \
  cd osslsigncode-osslsigncode-e72a1937d1a13e87074e4584f012f13e03fc1d64 && \
  ./autogen.sh

RUN cd osslsigncode-osslsigncode-e72a1937d1a13e87074e4584f012f13e03fc1d64 && ./configure CFLAGS='-g -O3' GSF_LIBS='-l:libgsf-1.a -lgobject-2.0 -lglib-2.0 -lxml2 -l:libz.a -l:libbz2.a' && make install

CMD cp /usr/local/bin/osslsigncode /files
