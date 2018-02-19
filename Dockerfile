FROM ruby:2.5.0-slim-stretch
RUN apt-get update && apt-get install -y ffmpeg
COPY . /app
RUN mkdir /var/anubarak
WORKDIR /app
CMD ruby server.rb