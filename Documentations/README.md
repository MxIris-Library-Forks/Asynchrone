# 文档索引

- [Evolutions/README.md](Evolutions/README.md)：提案状态表。
  - [Evolutions/draft-rework-racing-and-throttle.md](Evolutions/draft-rework-racing-and-throttle.md)：重写 `debounce` / `combineLatest` 的竞速逻辑，让 `throttle` 按时间窗发出。Draft。
  - [Evolutions/draft-multi-sequence-error-typing-and-arity.md](Evolutions/draft-multi-sequence-error-typing-and-arity.md)：堵住 `zip` / `combineLatest` / `chain` 只看第一个上游而吞掉错误的漏洞，并支持任意个数的上游。Accepted。
- [Internal/CodeReviewRulings.md](Internal/CodeReviewRulings.md)：code review 中判为误报、不修或只改文档的发现，以及当时的理由。
