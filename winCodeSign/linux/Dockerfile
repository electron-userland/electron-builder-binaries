FROM ubuntu

RUN apt-get update
RUN apt-get install -y curl libssl-dev libcurl4-openssl-dev libgsf-1-dev autoconf build-essential

# Download and install osslsigncode
RUN curl -L "http://downloads.sourceforge.net/project/osslsigncode/osslsigncode/osslsigncode-1.7.1.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fosslsigncode%2Ffiles%2Fosslsigncode%2F&ts=1413463046&use_mirror=optimate" | tar -xz
WORKDIR osslsigncode-1.7.1
RUN ./configure
RUN make
RUN make install 

CMD cp /usr/local/bin/osslsigncode /files
