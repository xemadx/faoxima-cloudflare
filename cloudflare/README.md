# اجرای Faoxima روی Cloudflare

فاکسیما فروشگاه و سامانهٔ مدیریت اشتراک VPN در تلگرام است. ربات سفارش، پرداخت، تمدید، تحویل کانفیگ و پشتیبانی را مدیریت می‌کند. پنل‌های VPN جداگانه سرویس کاربران را می‌سازند و ترافیک آن‌ها را عبور می‌دهند.

در این نسخه Worker ورودی HTTPS و زمان‌بندی را مدیریت می‌کند. یک Cloudflare Container کد اصلی PHP 8.3 را برای وب‌هوک‌ها، مینی‌اپ، پنل مدیریت، API، لینک اشتراک، ربات‌های نماینده و وظایف پس‌زمینه اجرا می‌کند. MySQL دو پایگاه‌داده دارد. یکی برای تراکنش‌های خود فاکسیما و دیگری برای فایل‌سیستم JuiceFS که نشست‌ها، صف‌ها، تنظیمات و فایل‌های ربات‌های نماینده را میان ری‌استارت‌ها نگه می‌دارد. این معماری به یک میزبان مستقل برای اجرای PHP نیاز ندارد. [Cloudflare Containers](https://developers.cloudflare.com/containers/) · [ذخیره‌سازی JuiceFS در MySQL](https://juicefs.com/docs/community/reference/how_to_set_up_object_storage/#mysql)

## پیش‌نیازها

- حساب Cloudflare با Workers Paid و Containers، Docker با Buildx، و Node.js 24.
- یک MySQL 8 در دسترس کانتینر با TLS و گواهی معتبر برای نام میزبان. دو schema خالی مثل `faoxima` و `faoxima_files` بسازید و به یک کاربر مجزا روی همان دو schema دسترسی DDL و خواندن و نوشتن بدهید. برای MariaDB و سرویس‌های سازگار با MySQL، ابتدا migration را روی یک دیتابیس staging بررسی کنید.
- هر استقرار یک ربات اصلی و ربات‌های نمایندهٔ آن را اجرا می‌کند. برای چند ربات اصلی، نام Worker و دو schema مستقل برای هر استقرار تعریف کنید.
- توکن و نام کاربری ربات تلگرام و شناسهٔ عددی مدیر اصلی. نام کاربری را بدون `@` وارد کنید.
- درگاه‌ها و پنل‌های VPN باید از محل اجرای Container دسترسی‌پذیر باشند. برای سرویس‌هایی که به شبکه یا IP مبدأ مشخص محدودند، دسترسی هر اتصال را پیش از انتقال عملیاتی بررسی کنید.
- حداکثر حجم آپلود عمومی تابع محدودیت HTTP دامنه در Cloudflare است. [Cloudflare Workers Limits](https://developers.cloudflare.com/workers/platform/limits/#request-limits)

## انتشار

۱. در `cloudflare/wrangler.jsonc` مقدار `PUBLIC_URL` را روی URL نهایی HTTPS تنظیم کنید. آدرس باید یک بخش مسیر داشته باشد، برای مثال `https://shop.example.com/faoxima`. برای دامنهٔ اختصاصی Cloudflare همان hostname را به‌عنوان Custom Domain این Worker ثبت کنید. `workers.dev` هم قابل استفاده است. [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)

۲. از یک کپی تمیز مخزن ایمیج را بسازید. `cloudflare/.dev.vars.example` نام متغیرها را نشان می‌دهد. فایل محلی `cloudflare/.secrets.json` را با متغیرهای دیتابیس و تلگرام بسازید. همهٔ مقادیر آن باید رشته باشند و `PUBLIC_URL` در تنظیم Wrangler بماند. در صورت استفاده از CA خصوصی، متن PEM را در `DB_CA_PEM` بگذارید. `DB_TLS` به‌صورت پیش‌فرض `1` است. برای Redis اختیاری متغیرهای `REDIS_*` را اضافه کنید. [Worker Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)

۳. از پوشهٔ `cloudflare` اجرا کنید.

```sh
npm ci
npm run check
npx wrangler login
npm run deploy -- --secrets-file .secrets.json
```

`npm run check` باندل Worker و تنظیم Wrangler را بررسی می‌کند. استقرار ایمیج را هم می‌سازد. سرور داخلی پس از آماده شدن فایل‌سیستم و تأیید schema درخواست می‌پذیرد. اولین راه‌اندازی می‌تواند چند دقیقه طول بکشد. [راهنمای استقرار Cloudflare Containers](https://developers.cloudflare.com/containers/get-started/)

۴. بعد از باز شدن مینی‌اپ، در محیط اجرای محلی `PUBLIC_URL` و `TELEGRAM_BOT_TOKEN` و در صورت استفاده `TELEGRAM_WEBHOOK_SECRET` را تنظیم کنید. فرمان زیر وب‌هوک و دکمهٔ فروشگاه همان ربات را در Telegram تنظیم می‌کند و URL ثبت‌شده را می‌خواند.

```sh
npm run webhook
npm run webhook -- --verify
```

مینی‌اپ در `/faoxima/app/`، پنل مدیریت در `/faoxima/panel/` و وب‌هوک تلگرام در `/faoxima/index.php` خواهد بود. مدیر اصلی می‌تواند اطلاعات ورود پنل وب را از منوی ادمین ربات تنظیم کند. Worker هر دقیقه کرون اصلی فاکسیما را از پورت خصوصی کانتینر فراخوانی می‌کند. زمان اجرای jobها در کد فاکسیما همچنان تهران است. [Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/) · [Telegram Mini Apps](https://core.telegram.org/bots/webapps)

## انتقال نصب فعلی

ابتدا بکاپ MySQL را در `DB_NAME` وارد کنید. برای حفظ وضعیت خارج از دیتابیس، یک کپی از نصب قبلی نگه دارید و فایل‌های تولیدشده در `storage/`، `cronbot/.runtime/`، فایل‌های صف در `cronbot/` و پوشه‌های ساخته‌شده برای ربات‌های نماینده در `vpnbot/` را به دایرکتوری `app/` روی volume انتقال دهید. در صورت شخصی‌سازی، `text.json`، `default_help.json` و `optimization_config.php` را هم منتقل کنید. `config.php` قدیمی را با Worker Secrets جایگزین کنید. برای بکاپ زیرساخت، هر دو schema و تنظیمات Worker Secrets را در نظر بگیرید. پس از شروع اولین کانتینر، `faoxima_files` یک volume با فرمت JuiceFS است و می‌توان برای انتقال فایل‌ها همان volume را از یک میزبان مدیریتی دارای FUSE و دسترسی MySQL mount کرد. [راهنمای mount در JuiceFS](https://juicefs.com/docs/community/command_reference/#juicefs-mount)

هنگام جابه‌جایی ربات موجود، از اجرای هم‌زمان کرون نصب قدیم و Cron Trigger نصب جدید روی یک دیتابیس جلوگیری کنید. ثبت وب‌هوک جدید، مقصد به‌روزرسانی‌های بعدی را عوض می‌کند. اگر hostname یا بخش مسیر تغییر کرده، URL ربات‌های نماینده، پنل‌ها، درگاه‌ها و لینک اشتراک را هم به مقصد جدید منتقل کنید.

## آزمون پذیرش

- مینی‌اپ و دارایی‌هایش باز شوند. پنل وب بتواند نشست ادمین را بین دو درخواست و بعد از ری‌استارت بازیابی کند.
- ربات آزمایشی `/start` را پاسخ بدهد و یک سفارش فروش دستی، رزرو، تمدید و تحویل کانفیگ تکمیل شود.
- هر پنل و درگاه فعال با حساب آزمایشی خودش بررسی شود. تست پرداخت باید بررسی callback و ثبت یک‌بارهٔ تراکنش را شامل شود.
- یک ربات نماینده، یک صف ارسال و یک job زمان‌بندی‌شده پس از تعویض کانتینر قابل استفاده بمانند.
- ابزار مدیریت سرور `install.sh` و phpMyAdmin متعلق به استقرار VPS هستند. این استقرار مدیریت ایمیج را به Wrangler و مدیریت دیتابیس را به سرویس MySQL می‌سپارد.
