FROM alpine

RUN echo "coucou"

CMD echo '{"perf":0.9876}' > /data/perf.json
