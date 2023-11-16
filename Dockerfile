FROM klakegg/hugo:ext-debian

CMD ["serve", "--cleanDestinationDir", "--themesDir", "../..", "--baseURL",  "http://localhost:1313/katalyst-website/", "--buildDrafts", "--buildFuture", "--disableFastRender", "--ignoreCache", "--watch"]