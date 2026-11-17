color: T.acc, borderRadius: BorderRadius.circular(20)),
                          child: const Text('ویرایش‌شده توسط هوش مصنوعی',
                              style: TextStyle(color: T.bg, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    if (p.note.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(p.note, style: const TextStyle(color: T.hi, fontSize: 13))),
                    const SizedBox(height: 8),
                    if (p.items.isEmpty)
                      const Text('برنامه‌ای ثبت نشده', style: TextStyle(color: T.tx2))
                    else
                      for (final it in p.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            const Icon(Icons.circle, size: 7, color: T.acc),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text('${it.part}${it.subject.isEmpty ? '' : ' — ${it.subject}'}')),
                            Text(
                                '${fmtMin(it.minutes)}${it.testsTarget > 0 ? ' · ${fa(it.testsTarget)} تست' : ''}',
                                style: const TextStyle(color: T.tx2, fontSize: 12)),
                          ]),
                        ),
                  ]),
                ),
              ),
              ),
          ]),
        ),
      ]),
    );
  }
}
