# Astral AI — وكيل الذكاء الاصطناعي المستقل لـ iOS

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138)](https://swift.org)
[![License](https://img.shields.io/badge/license-UNIRAL-8A2BE2)](#المطور-والحقوق)

> **Astral AI** — وكيل ذكاء اصطناعي مستقل (الإصدار 5.0.0) (على طريقة Manus) يعمل بالكامل على جهازك، ويعمل الآن داخل **astra-os 5.0** — كمبيوتر حقيقي بأسلوب Claude Code يملكه الوكيل: **شل كامل** في `/home/astral` بأنابيب (`cmd | cmd`) وسَلسلة (`&&` و `;`) وإعادة توجيه، ينفّذ الأوامر، ينشئ الملفات ويحفظها، يبحث في الإنترنت الحي ويقرأ الصفحات، ويطلق وكلاء فرعيين متوازيين — وترى كل أمر ينفّذه في شريط كمبيوتر أسترا فوق صندوق الإرسال، أو تشغّل الطرفية بنفسك من زر Terminal.

---

## المزايا الرئيسية

| الركيزة | ما الذي تحصل عليه |
| --- | --- |
| **زر الإجراء — إجابة فوق أي شاشة بدون فتح التطبيق (جديد في V5.0.0)** | أعيد بناء تجربة زر Action Button من الجذور: اضغط الزر واكتب مهمتك، و**إجابة أسترا تظهر فورًا فوق الشاشة اللي قدامك — التطبيق لا يُفتح نهائيًا** ولا يمر عبر تطبيق الاختصارات. نسخة من الإجابة توصل إشعار، والمحادثة كاملة تنتظر في سجل التطبيق أول ما تفتحه. لو السؤال يحتاج الوكيل الكامل، المهمة تُحفظ وتشتغل لحظة فتح التطبيق. | 
| **كمبيوتر بنسبة 100% — محليًا وسحابيًا (جديد في V5.0.0)** | **محليًا**: astra-os بقى شل حقيقي كامل — أنابيب (`cat log | grep خطأ | sort | uniq -c`)، سَلسلة بـ `&&` و `;` بمعاني exit code الحقيقية، و 16 أمر جديد (sort، uniq، cut، tr، rev، diff، seq، base64، md5sum، shasum، df، env، which، chmod، basename، dirname، sleep). **سحابيًا**: الوكيل معاه **صلاحيات root** — أي أمر يُرفض بصلاحية يُعاد تلقائيًا بـ sudo، و apt و ffmpeg والترجمة وكل حاجة تشتغل، مع أداة `cloud_file_push` الجديدة لرفع ملفاتك للجهاز السحابي (المرآة اكتملت: رفع + تنزيل). | 
| **تلميع الواجهة والأنيميشن (جديد في V5.0.0)** | أيقونة وضع الدردشة/الوكيل بتتبدل بتأثير crossfade ناعم مع scale + نبضة اهتزاز خفيفة عند التبديل، وزر الإرسال في التشغيل السريع «بيتنفس» ويكبر لحظة كتابة أول حرف — كل تفاعل بيرد عليك بإحساس حقيقي. | 
| **زر الإجراء — مهمة بضغطة واحدة (V4.6.0)** | اختر Astral ← Quick Task من إعدادات الآيفون (بدون بناء أي اختصار)، وواجهة **التشغيل السريع** الإبداعية (نجوم متحركة + كرة خضراء حية + نبضة اهتزاز) متاحة من داخل التطبيق ودليل إعداد من 3 خطوات في الإعدادات. |
| **صلاحية السكرين شوت للوكيل (جديد في V4.6.0)** | اطلب من الوكيل «ابعتلي سكرين شوت من الموقع اللي انت فيه» — أداة `browser_screenshot` الجديدة تلتقط الصفحة الحالية (حتى لو المتصفح مغلق، عبر التقاط مسرحي غير مرئي) وتسلّمها كبطاقة صورة داخل المحادثة، مع نسخة محفوظة في `Screenshots/` وعارض تكبير بملء الشاشة. |
| **كرة العمل الخضراء رجعت (جديد في V4.6.0)** | بناءً على طلبك رجعنا كرة التحميل الأصلية: حلقة فضية + قلب أخضر + قمر دوّار من جوه — نفس كرة الطرفية اللي بتحبها، الآن موحّدة كلون واحد لكل حالات «الجهاز شغال» في التطبيق كله (الهيدر، لوحة المهام، الخطة، الوكلاء الفرعيون، المتصفح، الطرفية). |
| **إصلاح أيقونة الرسائل + محرك الأقواس (جديد في V4.6.0)** | اكتشفنا وإصلاحنا عيبًا جذريًا في محرك SVG: تصحيح نصف القطر كان مقلوبًا، فكان يرسم قوس `message-circle` كحلقة هاربة خارج إطار الزر — الأيقونة الآن فقاعة رسالة Lucide حقيقية بمقاس مضبوط داخل كبسولة واضحة الحدود في وضع المحادثة والوكيل. |
| **سلاسة تنقل مُحسّنة (جديد في V4.6.0)** | الرسائل الجديدة تنساب لداخل المحادثة (ظهور + صعود من الأسفل) بدل الظهور المفاجئ، تبويبات الطرفية صارت لها «إبهام» زجاجي واحد ينزلق بينها (matchedGeometry)، وحالة «يفكر…» تظهر بأنيميشن ناعم — لغة حركة واحدة متسقة في كل التطبيق. |
| **حدود الأدوات أُلغيت — استكشاف بلا سقف (جديد في V4.5.6)** | رفعنا كل السقوف: حلقة المحادثة 60 دورًا، الوكلاء الفرعيون 30، والمنفّذ 40 — والنموذج ممنوع صراحةً من الاستسلام بعبارة «وصلت لحد الأدوات». سلاسل البحث الطويلة والتنقيب العميق يكملوا للآخر حتى تتحصل على ملخص نهائي كامل. |
| **شريط الوكلاء يختفي بعد انتهاء المهمة (جديد في V4.5.6)** | لما الوكلاء المتوازيون يخلصوا شغلهم، شريط الـ Agents وبطاقة خطة التنفيذ ولوحة المهام يتلاشوا تلقائيًا بعد لحظات — المحادثة ترجع نظيفة بهدوء بعد كل مهمة مكتملة. |
| **تثبيت المهارات من المرفقات تلقائيًا (جديد في V4.5.6)** | ارفق ملف `.skill` أو `.json` في أي رسالة — يتثبت فورًا في قسم المهارات مع رسالة تأكيد، ويقدر الوكيل كمان يثبّت من مسار محلي أو رابط عبر `skill_install`. |
| **66 أيقونة Lucide + هوية بصرية موحدة (جديد في V4.5.6)** | 15 أيقونة جديدة محمّلة من الإنترنت (منها loader-circle الدوّار و panel-left و message-square-plus) — الهيدر والكومبوزر وشريط الوكلاء وكل أزرار التطبيق صارت بمجموعة واحدة متناسقة، بدل الأشكال المرسومة يدويًا. |
| **سهم رجوع احترافي + زر ✕ بستايل Manus (جديد في V4.5.6)** | سهم الرجول صار أيقونة Lucide vector نظيفة داخل زر زجاجي دائري (يعكس صح في العربي)، وواجهة الكمبيوتر الكاملة صارت بتُغلق بزر ✕ دائري وعنوان «كمبيوتر أسترا» مع حالة فارغة أنيقة على طريقة Manus. |
| **كمبيوتر أسترا — فوتر طبقي بأسلوب Manus (جديد في V4.5.2)** | المحادثة بقت نظيفة: الخطوات والردود بس. كل ما الوكيل ينفّذه (أوامر طرفية، تصفح، ملفات) يتدفق لايف في شريط **Astra Computer** الزجاجي فوق صندوق الإرسال — لمسة واحدة تفتح الكمبيوتر كامل. |
| **مبدّل الكمبيوتر: محلي / سحابي (جديد في V4.5.2)** | الإعدادات ← الكمبيوتر: بطاقتان — **محلي (iPhone)** أو **سحابي (Ubuntu)**. لما تختار السحابي، التطبيق كله ينفّذ على جهاز أوبونتو الحقيقي (exec + بايثون + طرفيتك)، والملفات تتزامن صعودًا/هبوطًا بين الجهازين. **الجهاز السحابي يُطفأ تلقائيًا فور انتهاء كل مهمة** — رصيدك ما بيتمحرقش أبدًا. |
| **إصلاح تشغيل السحابي 400 (جديد في V4.5.2)** | السبب الجذري لخطأ "Error at /templateId" كان جسم الطلب بدون حقل `templateID` الإجباري — الآن يُرسل بالمواصفات الرسمية (v2 API + قالب Ubuntu `base`) + مفتاح مدمج يعمل من أول تشغيل. |
| **مشاريع وملفات مساحة العمل (جديد في V4.5.2)** | زر مشروع جديد في تبويب الملفات ينشئ `Projects/<اسمك>/` مع README — أنت والوكيل تشتغلوا جواه مع بعض. أداة `project_create` للوكيل + استيراد ملفات من تطبيق الملفات مباشرة + أي ملف ترفقه في المحادثة يُنسخ لـ `uploads/` ليشتغل عليه الوكيل. |
| **تحميل المهارات من الإنترنت (جديد في V4.5.2)** | أرسل للوكيل رابط ملف `.skill` وهو ينزّله ويحفظه في مكتبة المهارات فورًا عبر أداة `skill_install`. |
| **51 أيقونة Lucide احترافية (جديد في V4.5.2)** | نظام أيقونات متجهي كامل داخل التطبيق: مُفسّر SVG أصلي (كل أوامر المسارات + الأقواس البيضاوية) يرسم أيقونات Lucide المرخّصة (MIT) المحمّلة من الإنترنت — حادة في أي حجم وأي لون، في الفوتر والتلاميذ والطرفية. |
| **سهم الرجوع الزجاجي في كل مكان (جديد في V4.5.2)** | شاشات "عن التطبيق" و"الكمبيوتر السحابي" صارت تستخدم سهم الرجول الزجاجي المخصص — لا مزيد لكلمة "الإعدادات" مكان السهم بعد تغيير اللغة. |
| **الكمبيوتر الشخصي للذكاء الاصطناعي (جديد في V4.0)** | جهاز حقيقي للوكيل جوه التطبيق: بيئة astra-os في `/home/astral` + **بايثون حقيقي** (CPython 3.12 عبر Pyodide WASM) + **جافاسكريبت حقيقي** (JavaScriptCore) — أدوات `run_python` و `run_javascript` وأوامر `python3` و `node` و `pip install` مباشرة في الطرفية. |
| **لينكس سحابي حقيقي 100% (جديد في V4.0)** | اربط مفتاح E2B المجاني (نفس بنية Manus) من الإعدادات ← يحصل الوكيل على جهاز **Ubuntu كامل**: bash حقيقي، apt، بايثون بـ pip، git، ترجمة برامج — أدوات `cloud_exec` و `cloud_file_pull` + تبويب "السحابي" في الطرفية تنفّذ فيه أوامرك بنفسك. يعمل عند الحاجة ويُطفأ تلقائيًا عند الخمول. |
| **محرك أدوات كوني — نهاية عصر الشات بوت (جديد في V4.0)** | أي موديل من أي مزود صار وكيلًا حقيقيًا: لو المزود يدعم Function Calling نستخدمه، ولو مش بيدعمه أو رفض المخططات، يشتغل تلقائيًا **بروتوكول الأدوات النصي** (ASTRAL_TOOL) — الأدوات نفسها، التنفيذ نفسه، بدون أي ترقية صامتة لشات بوت. يشمل أيضًا المزودين المخصصين بالكامل (مسارات Dot-Path). |
| **شارات دعم الأدوات في قائمة الموديلات (جديد في V4.0)** | كل موديل من OpenRouter يظهر بشارة "أدوات أصلية" أو "بروتوكول نصي" (من `supported_parameters`) — تعرف قبل الاختيار إن كان الموديل يقود الأدوات فورًا. |
| **بيئة عمل astra-os (V3.5)** | طرفية افتراضية لينكسية الطابع في `/home/astral` — نفس جهاز الوكيل وجهازك: ينفّذ أمر `exec` أوامر حقيقية (ls، cd، cat، echo بإعادة التوجيه > >>، mkdir، grep، find، sed، tree، curl، search…) وترى النتائج كبطاقة طرفية مباشرة داخل المحادثة، أو افتحها بنفسك من زر Terminal وتنفّذ أوامرك يدوياً. |
| **البحث الحي وقراءة الويب (V3.5)** | أدوات `web_search` و `web_fetch` + أوامر `search` و `curl` في الطرفية — يبحث في الإنترنت الحي (Bing/DuckDuckGo بدون مفاتيح)، يقرأ الصفحات كاملة، ويوثّق المصادر في إجابته. |
| **لوحة مهام الوكيل بستايل iOS 27 (V3.6/V4.0)** | أداة `update_tasks` — النموذج نفسه يحدد التودو ليست ويحدّث حالتها لحظة بلحظة، وتظهر في شريط **Liquid Glass كامل** (زجاج iOS 26/27 التفاعلي + كبسولة العداد + انتقالات نابضة) داخل المحادثة — تجربة TodoWrite من Claude Code بالكامل. |
| **سجل نشاط الوكيل المباشر (V3.6)** | تبويب "الوكيل" في الطرفية: كل ما يفعله الذكاء الاصطناعي يظهر لايف — كل بحث ويب، قراءة صفحة، أمر طرفية، ملف أو كود — بالمدة والحالة والنتيجة القابلة للتوسيع، زي كونسول Claude Code. |
| **مخصص المزودين والنماذج** | اتصل بأي مزود متوافق مع OpenAI (OpenAI، OpenRouter، Groq، LM Studio...) أو بخادم محلي مثل Ollama — أو عرّف بروتوكولًا مخصصًا بالكامل عبر مسارات Dot-Path. مفتاحك يبقى في Keychain على جهازك. |
| **التخطيط والتنفيذ الذاتي + وكلاء متوازيون** | يحوّل الوكيل هدفك إلى خطة خطوات مرئية وينفذها أداةً تلو الأداة، ويوزّع الخطوات القابلة للتوزيع على وكلاء فرعيين يعملون في وقت واحد ثم يدمج نتائجهم في مخرج واحد. |
| **متصفح تفاعلي حي** | يفتح الوكيل صفحات الويب، ينقر، يكتب، يمرّر، ويستخرج النصوص والعناصر — وترى أنت كل ما يحدث لحظة بلحظة ويمكنك التدخل في أي وقت. |
| **مصنع الملفات + ماركداون كامل** | يكتب الوكيل الملفات مباشرة في مساحة عمل داخل التطبيق (تقارير Markdown، جداول CSV، أكواد، أرشيفات ZIP) — تظهر في تبويب الملفات **وفي تطبيق "الملفات" على الآيفون** (On My iPhone ← Astral) — مع عارض ماركداون كامل وتصدير ZIP بضغطة واحدة. |
| **الخلفية + الأنشطة الحية والجزيرة الديناميكية** | المهام الطويلة تستمر في الخلفية وتتابعها من الشاشة المقفلة عبر Live Activity يعرض الهدف والخطوة الحالية ونسبة التقدم — مباشرة في الجزيرة الديناميكية. |
| **تكامل النظام** | رابط عميق `astral://` واختصارات، إنشاء أحداث تقويم وتذكيرات، إشعارات محلية، ومشاركة نصوص وصور وروابط إلى الوكيل من أي تطبيق عبر امتداد المشاركة. |

## لقطات الشاشة

> لقطات الشاشة ستُضاف قريبًا إلى هذا القسم: السماء النجمية الحية، البطاقات الزجاجية، الخط الزمني المتوهج للخطة، المتصفح الحي، وعارض الماركداون الكامل.

## البنية المعمارية

```
AstralAI/
├── App/             نقطة الدخول والجذر التركيبي: AstralApp وAppEnvironment وRootView والتوطين AR/EN
├── Core/            العقود المشتركة (Contracts.swift) — الأنواع والبروتوكولات المركزية للمشروع كله
├── DesignSystem/    نظام تصميم Liquid Glass: الثيم، الزجاج، حقل النجوم، شريط التبويب العائم، المكونات
├── Infra/           البنية التحتية: عميل LLM المتدفق، محلل SSE، DotPath، مستخرج JSON، مساحة العمل، Keychain
├── AgentCore/       عقل الوكيل: المخطط، المنفّذ، الوكلاء الفرعيون المتوازون، الأدوات، دمج النتائج
├── Features/        شاشات SwiftUI: المحادثة، الخطة، المتصفح، الملفات، الإعدادات، شاشة الترحيب
├── Platform/        خدمات النظام: الإشعارات، النشاط الحي، التقويم والتذكيرات، مهام الخلفية
├── Widgets/         امتداد WidgetKit: ودجات الشاشة الرئيسية والنشاط الحي
├── ShareExtension/  امتداد المشاركة: أرسل نصوصًا وصورًا وروابط إلى الوكيل من أي تطبيق
├── WidgetsShared/   المشترك بين التطبيق والودجات: مجموعة التطبيق، سمات النشاط، مخزن الحالة
└── Tests/           حزمة اختبارات XCTest لمحركات المنطق الأساسية
```

## البناء من المصدر

**المتطلبات:** macOS 14 أو أحدث، Xcode 16 أو أحدث (يشمل iOS 17 SDK)، و[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/uniralhadith-create/AstralAI.git
cd AstralAI
xcodegen generate
open AstralAI.xcodeproj
# في Xcode: اختر هدف AstralAI ومحاكي iPhone ثم اضغط Cmd+R
```

**البناء عبر CI:** كل دفعة إلى `main` وكل وسم (tag) يشغّل GitHub Actions على macOS runner: توليد المشروع بـ XcodeGen، بناء التطبيق، تشغيل الاختبارات، ثم تغليف IPA غير موقّع يُرفق بالـ Artifacts وصفحة Releases.

**تشغيل الاختبارات:**

```bash
xcodebuild test -scheme AstralAI -destination 'platform=iOS Simulator,name=iPhone 16'
```

أو من Xcode مباشرة: `Cmd+U`. حزمة الاختبارات (84 اختبارًا) تغطي محركات المنطق الأساسية: DotPath، محلل SSE، مستخرج JSON، عقود Codable، محلل الماركداون، عارض الرياضيات، ملوّن الكود، ومساحة العمل مع ZIP — كلها حتمية بدون شبكة أو مؤقتات.

## إعداد المزودين

### المزودون الجاهزون

يوجد الآن زر **«إعداد سريع»** في شاشة إضافة المزود يملأ الرابط والبروتوكول والنماذج المقترحة تلقائيًا.

| المزود | العنوان الأساسي (Base URL) | مفتاح API | ملاحظات |
| --- | --- | --- | --- |
| OpenAI | `https://api.openai.com/v1` | مطلوب | `gpt-4o`, `gpt-4o-mini` |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` | مطلوب | مجاني من build.nvidia.com (يبدأ بـ `nvapi-`) |
| xAI Grok | `https://api.x.ai/v1` | مطلوب | `grok-4`, `grok-3` |
| AWS Bedrock | `https://bedrock-runtime.us-east-1.amazonaws.com` | `ACCESS_KEY:SECRET_KEY` | توقيع SigV4 أصلي + Converse API مع البث والأدوات؛ غيّر المنطقة في الرابط حسب حسابك |
| OpenRouter | `https://openrouter.ai/api/v1` | مطلوب | مئات النماذج خلف مفتاح واحد |
| Groq | `https://api.groq.com/openai/v1` | مطلوب | استدلال فائق السرعة |
| DeepSeek | `https://api.deepseek.com/v1` | مطلوب | `deepseek-chat`, `deepseek-reasoner` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | مطلوب | نقطة النهاية المتوافقة مع OpenAI |
| Ollama (محلي) | `http://localhost:11434/v1` | غير مطلوب | إصدارات Ollama الحديثة متوافقة مع OpenAI على `/v1`؛ أو استخدم بروتوكولًا مخصصًا للواجهة الأصلية `/api/chat` (انظر المثال أدناه) |
| LM Studio (محلي) | `http://localhost:1234/v1` | اختياري | شغّل الخادم المحلي من تطبيق LM Studio أولًا |

> مع المزودين المحليين لا حاجة لأي مفتاح — اترك الحقل فارغًا.

### استكشاف نقطة النهاية تلقائيًا

لم يعد شكل الرابط مصدر أخطاء: يقبل التطبيق الرابط مع `/v1` أو بدونه أو حتى رابط كامل ينتهي بـ `/chat/completions`، ثم **يجرب المرشحين بالترتيب** (مع `/v1` ثم بدونه) حتى ينجح الاتصال. رسائل الأخطاء أصبحت تشخيصية وواضحة (مفتاح خاطئ / رابط خاطئ / حد طلبات / انقطاع شبكة) وباللغتين.

### أدوار النماذج

| الدور | الاستخدام | التوصية |
| --- | --- | --- |
| **النموذج الرئيسي (Main)** | المحادثة وتوليد الردود والاستدعاء العام | نموذج متوازن قوي |
| **نموذج المخطط (Planner)** | توليد خطط التنفيذ متعددة الخطوات | نموذج استدلالي قوي |
| **نموذج الوكيل الفرعي (Sub-Agent)** | تنفيذ الخطوات المتوازية | نموذج أسرع وأوفر |

إذا تُرك حقلا المخطط أو الوكيل الفرعي فارغين، يُستخدم النموذج الرئيسي تلقائيًا.

### البروتوكول المخصص ومسارات Dot-Path

عند اختيار «بروتوكول مخصص» تتحكم بكل تفاصيل الطلب والاستجابة:

| الإعداد | الوصف | القيمة الافتراضية |
| --- | --- | --- |
| `chatPath` | مسار نقطة نهاية المحادثة | `/v1/chat/completions` |
| `modelsPath` | مسار قائمة النماذج | `/v1/models` |
| `authHeaderName` / `authValueFormat` | ترويسة المصادقة وصيغة قيمتها (مثل `Bearer %@`) | `Authorization` / `Bearer %@` |
| `streamFormat` | صيغة البث: `sse` أو `ndjson` أو بدون | `sse` |
| `streamTextPath` | مسار مقطع النص في كل قطعة متدفقة | `choices.0.delta.content` |
| `fullTextPath` | مسار النص الكامل في الاستجابة غير المتدفقة | `choices.0.message.content` |
| `toolCallsPath` | مسار استدعاءات الأدوات | `choices.0.message.tool_calls` |
| `finishPath` | مسار سبب الانتهاء | `choices.0.finish_reason` |
| `modelsIDPath` | مسار معرفات النماذج | `data.[].id` |

**قواعد المسارات:** المفاتيح مفصولة بنقاط، والأرقام تفهرس المصفوفات (`choices.0` = العنصر الأول في `choices`)، و `[]` تطبّق ما بعدها على كل عنصر من عناصر المصفوفة (`data.[].id` = قائمة قيم `id` لكل عنصر في `data`).

**مثال — الواجهة الأصلية لـ Ollama عبر بروتوكول مخصص:**

| الإعداد | القيمة |
| --- | --- |
| Base URL | `http://localhost:11434` |
| `chatPath` | `/api/chat` |
| `modelsPath` | `/api/tags` |
| `streamFormat` | `ndjson` |
| `streamTextPath` | `message.content` |
| `finishPath` | `done` |
| `modelsIDPath` | `models.[].name` |

## المهارات (Skills)

تبويب «المهارات» يضيف سلوكيات خبيرة جاهزة للوكيل:

- **12 مهارة مدمجة**: البحث العميق، تطوير الويب، تحليل البيانات، تخطيط الرحلات، الكتابة الأكاديمية، مراجعة الكود، إنشاء المستندات، صناعة المحتوى، تحليل الأسواق، تعليم اللغات، هندسة الأوامر، تلخيص الاجتماعات.
- **تنزيل مهارات من رابط**: أي ملف JSON بصيغة `{ "skills": [...] }` أو مهارة مفردة.
- **استيراد من ملف** أو **إنشاء مهارة يدويًا** من داخل التطبيق.
- **التفعيل الفوري**: المهارة المفعّلة تُحقن تعليماتها في موجه النظام لكل جلسة، مع شريحة عدّاد حية في صندوق الكتابة.

```json
{
  "slug": "my-skill",
  "name": "My Skill",
  "name_ar": "مهارتي",
  "summary": "What it does",
  "instructions": "You are operating as ... (follow this protocol strictly)",
  "tools": ["web_search", "file_write"],
  "triggers": ["keyword"]
}
```

## الأيقونة التكيفية

أيقونة التطبيق (شعار الذرة المرسوم يدويًا) أصبحت متكيفة بالكامل مع iOS الحديث عبر كتالوج الأصول بمظاهر ثلاث: **فاتح** (الخلفية الأصلية كما هي)، **داكن** (نفس الرسمة بخطوط بيضاء على خلفية فحمية)، و**ملوّن/شفاف (Tinted)** حيث يطبّق النظام لون الصبغة على الرسمة — مع الحفاظ على شكل اللوجو الأصلي بكسلًا بكسلًا.

## الأمان والخصوصية

- مفاتيح API تُخزَّن **في iOS Keychain حصرًا** — ليست في UserDefaults ولا في أي ملف نصي.
- المفاتيح لا تغادر جهازك مطلقًا إلا داخل ترويسة الطلب الموجهة مباشرة إلى المزود الذي اخترته أنت.
- لا خوادم وسيطة ولا تحليلات تتبع؛ التطبيق يتصل بالمزود مباشرة من جهازك.
- ملفات مساحة العمل تبقى داخل حاوية التطبيق على جهازك، ويمكنك حذفها في أي وقت.

## التثبيت على الجهاز

يوزَّع التطبيق حاليًا كملف IPA غير موقّع يبنيه GitHub Actions — راجع [دليل التثبيت الكامل](INSTALL.md) لطرق AltStore وSideloadly وحساب المطور المدفوع.

## المطور والحقوق

> صُنع بعناية بواسطة **Tariq El-Fares** — المؤسس والرئيس التنفيذي، UNIRAL
>
> Instagram: [@astral.tariq](https://www.instagram.com/astral.tariq)

© 2026 UNIRAL — جميع الحقوق محفوظة.

---

# English

**Astral AI** is an autonomous, Manus-style AI agent that runs entirely on your iPhone or iPad. Give it a single goal and it plans, executes multi-step work with real tools, drives a live interactive browser, produces files in a built-in workspace with full Markdown rendering, and fans out parallel sub-agents for large tasks before merging their results — all inside a glowing **Liquid Glass** SwiftUI interface over a living starfield, fully bilingual (Arabic/English) from the first screen, with Live Activities tracking progress from the Lock Screen and Dynamic Island.

### Key Features

- **Custom providers & models** — any OpenAI-compatible provider (OpenAI, OpenRouter, Groq, LM Studio), local Ollama, or fully custom protocols mapped via Dot-Path. Keys stay in the iOS Keychain.
- **Autonomous planning & execution** — visible step plans, tool execution, and parallel sub-agents with result merging.
- **Live interactive browser** — open, click, type, scroll and extract, with full user visibility at every step.
- **File factory + full Markdown** — the agent writes Markdown/CSV/code/ZIP files into an in-app workspace rendered by a complete Markdown viewer (tables, highlighted code, math).
- **Background + Live Activities** — long tasks continue in the background and surface progress in the Dynamic Island.
- **System integration** — `astral://` deep links and shortcuts, calendar events, reminders, notifications, and a share extension.

### Architecture

```
AstralAI/
├── App/            Entry point, composition root, localization, root navigation
├── Core/           Shared contracts (Contracts.swift) — central types and protocols
├── DesignSystem/   Liquid Glass design system: theme, glass, starfield, floating tab bar
├── Infra/          Infrastructure: streaming LLM client, SSE parser, DotPath, JSON extractor, workspace, keychain
├── AgentCore/      The agent brain: planner, executor, parallel sub-agents, tools, merging
├── Features/       SwiftUI screens: chat, plan, browser, files, settings, onboarding
├── Platform/       System services: notifications, live activity, calendar, background tasks
├── Widgets/        WidgetKit extension: home widgets and the Live Activity
├── ShareExtension/ Share content into the agent from any app
├── WidgetsShared/  Shared between app and widgets: app group, activity attributes, status store
└── Tests/          XCTest unit suite for the core logic engines
```

### Building from Source

Requires macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
git clone https://github.com/uniralhadith-create/AstralAI.git
cd AstralAI
xcodegen generate
open AstralAI.xcodeproj
```

Run the deterministic test suite (84 tests, no network, no timers) with:

```bash
xcodebuild test -scheme AstralAI -destination 'platform=iOS Simulator,name=iPhone 16'
```

Every push to `main` and every tag runs GitHub Actions on a macOS runner, which generates the project, builds the app, runs the tests and packages an unsigned IPA into the release artifacts.

### Providers

Quick-setup presets (one tap) now include: OpenAI, NVIDIA NIM, xAI Grok, AWS Bedrock (native SigV4 + Converse streaming with tools), OpenRouter, Groq, DeepSeek, Mistral, Together, Google Gemini, Ollama and LM Studio. Endpoint auto-probing tries `/v1` and non-`/v1` variants automatically, so pasted URLs connect on the first try.

### Skills

The Skills tab ships 12 built-in expert skills (Deep Research, Web Developer, Data Analyst, …), downloads skills from any JSON URL, imports from files, and creates manual skills in-app. Enabled skills are injected into every agent system prompt — with a live counter chip in the composer.

| Provider | Base URL | API Key |
| --- | --- | --- |
| OpenAI | `https://api.openai.com` | Required |
| OpenRouter | `https://openrouter.ai/api/v1` | Required |
| Groq | `https://api.groq.com/openai/v1` | Required |
| Ollama (local) | `http://localhost:11434/v1` | Not required |
| LM Studio (local) | `http://localhost:1234/v1` | Optional |

**Model roles:** main (chat), planner (step planning — pick a strong reasoner), sub-agent (parallel execution — pick something fast). Empty planner/sub-agent fields fall back to the main model. Custom protocols map request/response fields via dot-paths: numeric segments index arrays (`choices.0`), `[]` maps over array elements (`data.[].id`). See the Arabic section above for a complete Ollama custom-protocol example.

### Security

API keys live only in the iOS Keychain and never leave your device except in the request header sent directly to your chosen provider. No middleman servers, no tracking.

### Installation

To install the unsigned IPA on your device (AltStore, Sideloadly, or a paid developer account), see the [installation guide](INSTALL.md).

### Credits

Developed by **Tariq El-Fares** — Founder & CEO, UNIRAL · Instagram: [@astral.tariq](https://www.instagram.com/astral.tariq) · © 2026 UNIRAL. All rights reserved.
