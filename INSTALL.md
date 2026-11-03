# دليل تثبيت Astral AI

كيف تحصل على التطبيق وتثبته على iPhone أو iPad — بدون App Store.

## ما الذي ستحصل عليه

يوزَّع Astral AI حاليًا كملف **IPA غير موقّع**:

- حمّل أحدث إصدار من صفحة **Releases** في مستودع المشروع على GitHub
- أو من تبويب **Actions** → آخر تشغيل ناجح → **Artifacts** → ملف الـ IPA
- يبني GitHub Actions التطبيق تلقائيًا على macOS runner مع كل إصدار، لذا لا تحتاج Mac للبناء — فقط للتوقيع والتحميل الجانبي (Sideload)

التوقيع يتم على جهازك بإحدى الطرق الثلاث أدناه، ولا يتطلب أي تعديل على التطبيق نفسه.

## المتطلبات

| المتطلب | التفاصيل |
| --- | --- |
| نظام التشغيل | iOS 17.0 أو أحدث (ميزة الأنشطة الحية نفسها متاحة من iOS 16.1، لكن الحد الأدنى للتطبيق هو 17.0) |
| الجهاز | iPhone أو iPad |
| Apple ID | حساب مجاني يكفي (توقيع 7 أيام متجددة)، أو حساب مطور مدفوع لتوقيع يدوم سنة |
| الحاسوب | Mac أو Windows حسب الطريقة، مع كابل USB |

## الطريقة 1: AltStore (مجانية — تجديد تلقائي كل 7 أيام)

1. حمّل **AltServer** من [altstore.io](https://altstore.io) وثبّته على الـ Mac أو Windows. على Mac: فعّل إضافة البريد (Mail Plug-in) من نافذة AltServer وأعد تشغيل Mail.
2. وصّل الـ iPhone بالحاسوب عبر USB، ثم من أيقونة AltServer في شريط القائمة اختر **Install AltStore** → اختر جهازك → أدخل Apple ID وكلمة المرور.
3. على الـ iPhone: افتح تطبيق AltStore → تبويب **My Apps** → زر **+** أعلى الشاشة → اختر ملف `AstralAI.ipa` → **Install**.
4. فعّل إذن الإشعارات لـ AltStore (الإعدادات → الإشعارات → AltStore) — الإذن لازم لكي يعمل التجديد في الخلفية.
5. تأكد أن الـ iPhone والحاسوب على **نفس شبكة Wi-Fi** دائمًا حتى يتجدد التوقيع تلقائيًا كل 7 أيام مع الحساب المجاني.
6. إذا ظهرت رسالة "Untrusted Developer" أول مرة، راجع قسم حل المشكلات أدناه.

## الطريقة 2: Sideloadly (الأسرع — Mac وWindows)

1. حمّل **Sideloadly** من [sideloadly.io](https://sideloadly.io) وثبّته.
2. وصّل الجهاز عبر USB وافتح Sideloadly.
3. اسحب ملف `AstralAI.ipa` وأفلته في نافذة البرنامج.
4. أدخل Apple ID (البريد وكلمة المرور) — يُستخدم محليًا لإصدار شهادة تطوير من Apple لتوقيع التطبيق.
5. اضغط **Start** وانتظر انتهاء التثبيت. تُدار مجموعات التطبيق (App Groups) تلقائيًا — لا تحتاج أي إعداد إضافي.
6. عند أول تشغيل، إن ظهرت رسالة توثيق فاتبع الخطوة نفسها في قسم حل المشكلات.

## الطريقة 3: حساب مطور مدفوع (99$ سنويًا — توقيع يدوم سنة)

1. اشترك في [Apple Developer Program](https://developer.apple.com/programs/).
2. **عبر Sideloadly أو AltStore:** نفّذ نفس خطوات الطريقتين أعلاه باستخدام Apple ID المدفوع — تُوقَّع التطبيقات لمدة سنة كاملة بدل 7 أيام.
3. **عبر Xcode من المصدر:** استنسخ المشروع، نفّذ `xcodegen generate`، افتح `AstralAI.xcodeproj`، ثم في تبويب Signing & Capabilities اختر فريقك (Team) لأهداف AstralAI وWidgets وShareExtension، وصِل جهازك واضغط Cmd+R.
4. ملاحظة: عند البناء من المصدر يدير Xcode مجموعة التطبيق `group.com.uniral.astralai` تلقائيًا عبر ملفات الـ entitlements.

## أول تشغيل: جولة الإعداد

1. **شاشة الترحيب:** اختر اللغة (العربية أو الإنجليزية) — يمكنك تغييرها لاحقًا من الإعدادات.
2. **أضف مزودًا:** الإعدادات → المزودون → زر **+** → اختر مزودًا جاهزًا (OpenAI، OpenRouter، Groq...) أو «مخصص» للمزودين المحليين (Ollama، LM Studio) → أدخل مفتاح API للمزودين السحابيين (اتركه فارغًا للمحليين).
3. **اختر النماذج:** حدّد النموذج الرئيسي، واختياريًا نموذج المخطط والوكيل الفرعي (اتركهما فارغين لاستخدام النموذج الرئيسي تلقائيًا).
4. **أطلق الوكيل:** ارجع إلى شاشة المحادثة واكتب هدفك — مثال: «ابحث عن أحدث أخبار استكشاف المريخ واكتب لي تقريرًا من صفحتين». سيعرض الوكيل خطته، ينفذها خطوة بخطوة، ويسلّمك الملفات الناتجة جاهزة للتصدير.

## حل المشكلات

| المشكلة | الحل |
| --- | --- |
| رسالة "Untrusted Developer" | لا تعني فشل التثبيت، وقد تظهر مرة واحدة مع التوقيع المجاني. الحل: الإعدادات → عام → VPN وإدارة الأجهزة → اختر Apple ID الخاص بك → اضغط **Trust** ثم افتح التطبيق من جديد. |
| أخطاء App Group أو تعطل التطبيق عند الفتح | أعد تثبيت الـ IPA بنفس الأداة وبنفس Apple ID — يجب أن تُنشأ الحاوية المشتركة `group.com.uniral.astralai` أثناء التوقيع (AltStore وSideloadly تدعمان ذلك تلقائيًا). |
| فشل الاتصال بالمزود | تحقق من Base URL (بما فيه `/v1` حيث يلزم) وصلاحية مفتاح API واتصال الإنترنت. للمزودين المحليين: تأكد أن الخادم يعمل وأن الجهاز يصل إليه على نفس الشبكة — جرّب عنوان IP الخاص بالحاسوب بدل `localhost` إذا لزم الأمر. |
| النشاط الحي (Live Activity) لا يظهر | الإعدادات → Astral → فعّل «الأنشطة الحية»، وتأكد من السماح بها على شاشة القفل (الإعدادات → Face ID ورمز الدخول → الأنشطة الحية)، وأن النظام iOS 16.1 أو أحدث (التطبيق يتطلب 17+ أصلًا). |
| توقف التطبيق عن العمل بعد أسبوع | سلوك طبيعي للتوقيع المجاني (7 أيام). افتح AltStore للتجديد مع تشغيل AltServer على نفس الشبكة، أو انتقل إلى حساب مطور مدفوع لتوقيع سنة. |
| لا أرى ملفات الوكيل في تطبيق «الملفات» | افتح تطبيق الملفات → **على جهازي** → **Astral AI** — مساحة العمل مفعّل فيها مشاركة الملفات افتراضيًا. |

## ملاحظة أمنية

- مفاتيح API تُخزَّن في Keychain على جهازك وحده، ولا تغادره إلا إلى المزود الذي اخترته مباشرة.
- إن استخدمت Apple ID مؤقتًا أو مفتاح API تجريبيًا لإتمام التثبيت والإعداد، **أبطله أو جدّده** بعد الانتهاء.
- لا تعيد توزيع نسخة IPA موقّعة ببياناتك — التوقيع مرتبط بحسابك ويمكن لـ Apple إبطاله.
- حمّل الـ IPA فقط من مستودع AstralAI الرسمي على GitHub، ولا تثبّت نسخًا من مصادر مجهولة.

---

# English — Installation Guide

Astral AI is currently distributed as an **unsigned IPA** built automatically by GitHub Actions. Download the latest build from the **Releases** page of the project repository (or the Artifacts of a successful **Actions** run), then sign and install it with one of the methods below.

## Requirements

- iOS 17.0 or later (Live Activities require iOS 16.1+, but the app itself targets 17.0), iPhone or iPad.
- A free Apple ID (7-day signing) or a paid Apple Developer account (1-year signing).
- A Mac or Windows computer with a USB cable, depending on the method.

## Method 1: AltStore (free, 7-day refresh)

1. Install **AltServer** from [altstore.io](https://altstore.io) on your Mac (enable the Mail plug-in) or Windows machine.
2. Connect your iPhone over USB and choose **Install AltStore** from the AltServer menu, signing in with your Apple ID.
3. On the iPhone, open AltStore → **My Apps** → **+** → select `AstralAI.ipa` → **Install**.
4. Allow notifications for AltStore (required for background refresh) and keep the phone and computer on the **same Wi-Fi** so the 7-day signature renews automatically.

## Method 2: Sideloadly (fastest)

1. Download **Sideloadly** from [sideloadly.io](https://sideloadly.io).
2. Connect your device, drag `AstralAI.ipa` into the window, enter your Apple ID, and press **Start**.
3. App Groups are handled automatically — no extra setup needed.

## Method 3: Paid developer account (99 USD/year)

Use the same AltStore/Sideloadly steps with your paid Apple ID for 1-year signing, or build from source in Xcode: `xcodegen generate`, open the project, set your team in Signing & Capabilities for the AstralAI, Widgets and ShareExtension targets, then press Cmd+R.

## First launch

1. **Onboarding:** pick your language (Arabic or English — switchable later in Settings).
2. **Add a provider:** Settings → Providers → **+** → choose a preset (OpenAI, OpenRouter, Groq) or Custom for local servers, then paste your API key (leave empty for local providers).
3. **Pick models:** set the main model, and optionally the planner and sub-agent models (empty fields fall back to the main model).
4. **Ask the agent:** type your goal in the chat and watch it plan, execute, and deliver the resulting files.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "Untrusted Developer" message | Not a failure — may appear once with free signing. Settings → General → VPN & Device Management → tap your Apple ID → **Trust**, then relaunch. |
| App Group errors / crash on launch | Reinstall the IPA with the same tool and Apple ID so the shared container `group.com.uniral.astralai` is created during signing. |
| Provider connection failed | Check the Base URL (including `/v1` where required), the API key, and connectivity. For local providers, verify the server is running and reachable — try your computer's IP instead of `localhost` if needed. |
| Live Activity not showing | Settings → Astral → enable Live Activities, allow them on the Lock Screen (Settings → Face ID & Passcode → Live Activities), and confirm iOS 16.1+ (the app requires 17+). |
| App stops working after a week | Expected with free Apple ID signing — refresh via AltStore (AltServer on the same network) or use a paid account. |

## Security note

API keys are stored only in the iOS Keychain and never leave your device except in the header sent directly to your chosen provider. If you used a temporary Apple ID or a throwaway API key during setup, **revoke or rotate it** when finished. Do not redistribute an IPA signed with your credentials, and only download builds from the official AstralAI repository.

---

Developed by **Tariq El-Fares** — Founder & CEO, UNIRAL · Instagram: [@astral.tariq](https://www.instagram.com/astral.tariq) · © 2026 UNIRAL
