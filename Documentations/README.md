# 文档索引

- [Evolutions/README.md](Evolutions/README.md)：提案状态表。
  - [Evolutions/draft-rework-racing-and-throttle.md](Evolutions/draft-rework-racing-and-throttle.md)：重写 `debounce` / `combineLatest` 的竞速逻辑，让 `throttle` 按时间窗发出。Deferred。
  - [Evolutions/draft-multi-sequence-error-typing-and-arity.md](Evolutions/draft-multi-sequence-error-typing-and-arity.md)：堵住 `zip` / `combineLatest` / `chain` 只看第一个上游而吞掉错误的漏洞，并支持任意个数的上游。Deferred。
- [Internal/CodeReviewRulings.md](Internal/CodeReviewRulings.md)：code review 中判为误报、不修或只改文档的发现，以及当时的理由。
- [Internal/MultiSequenceOperators.md](Internal/MultiSequenceOperators.md)：`zip` / `chain` 的会抛版与按系统版本拆开的重载是怎么实现的，为什么序列类型不带参数包，以及低于 macOS 15 时仍保留的吞错漏洞。
