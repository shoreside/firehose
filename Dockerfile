FROM ubuntu:trusty
RUN apt-get update

RUN apt-get install -y -q git ruby ruby-dev libxslt1-dev libxml2-dev make g++

RUN gem install --no-ri --no-rdoc bundler foreman rainbows sprockets

ADD . /firehose
WORKDIR /firehose
RUN bundle install --without development test
EXPOSE 7474

CMD ["/usr/local/bin/foreman", "start", "-d", "/firehose"]
