<?php

/*
|--------------------------------------------------------------------------
| Pooney admin settings schema
|--------------------------------------------------------------------------
| Every field below is editable in Admin → Beállítások and stored in the
| `settings` table (secrets encrypted with APP_KEY). The values here are
| only defaults. Field types: text, number, bool, select, secret, textarea.
*/

return [
    'settings' => [
        'general' => [
            'label' => 'Általános',
            'fields' => [
                'site.name' => ['label' => 'Webáruház neve', 'type' => 'text', 'default' => 'Pooney'],
                'site.tagline' => ['label' => 'Szlogen', 'type' => 'text', 'default' => 'Okos termékek, EU raktárból'],
                'site.email' => ['label' => 'Ügyfélszolgálati e-mail', 'type' => 'text', 'default' => 'info@pooney.com'],
                'site.phone' => ['label' => 'Telefonszám', 'type' => 'text', 'default' => ''],
                'site.order_notify_email' => ['label' => 'Új rendelés értesítés ide', 'type' => 'text', 'default' => 'orders@pooney.com'],
                'company.name' => ['label' => 'Cégnév (számlán)', 'type' => 'text', 'default' => ''],
                'company.address' => ['label' => 'Székhely', 'type' => 'text', 'default' => ''],
                'company.tax_number' => ['label' => 'Adószám', 'type' => 'text', 'default' => ''],
                'company.registration_number' => ['label' => 'Cégjegyzékszám', 'type' => 'text', 'default' => ''],
                'company.bank_account' => ['label' => 'Bankszámlaszám (átutaláshoz)', 'type' => 'text', 'default' => ''],
            ],
        ],

        'pricing' => [
            'label' => 'Árazás és ÁFA',
            'fields' => [
                'pricing.markup_percent' => ['label' => 'Alap haszonkulcs (%) a beszerzési ár felett', 'type' => 'number', 'default' => 85],
                'pricing.min_margin_huf' => ['label' => 'Minimális haszon / db (HUF)', 'type' => 'number', 'default' => 1500],
                'pricing.vat_rate' => ['label' => 'Alap ÁFA kulcs (%)', 'type' => 'number', 'default' => 27],
                'pricing.vat_mode' => ['label' => 'ÁFA kezelés', 'type' => 'select', 'default' => 'standard', 'options' => [
                    'standard' => 'Normál ÁFA (bruttó ár = nettó + ÁFA)',
                    'aam' => 'Alanyi adómentes (AAM) – nincs ÁFA',
                    'oss' => 'EU OSS – célország ÁFA (később)',
                ]],
                'pricing.eur_huf_rate' => ['label' => 'EUR → HUF árfolyam', 'type' => 'number', 'default' => 400],
                'pricing.usd_huf_rate' => ['label' => 'USD → HUF árfolyam', 'type' => 'number', 'default' => 365],
                'pricing.fx_buffer_percent' => ['label' => 'Árfolyam-puffer (%)', 'type' => 'number', 'default' => 3],
                'pricing.rounding' => ['label' => 'Kerekítés', 'type' => 'select', 'default' => '90', 'options' => [
                    'none' => 'Nincs', '10' => '10 Ft-ra', '90' => '...90 Ft végződés', '990' => '...990 Ft végződés',
                ]],
                'pricing.include_supplier_shipping' => ['label' => 'Beszállítói szállítás beépítése a termékárba', 'type' => 'bool', 'default' => true],
                'shipping.fee_gross' => ['label' => 'Szállítási díj (bruttó HUF / rendelés)', 'type' => 'number', 'default' => 1990],
                'shipping.free_above_gross' => ['label' => 'Ingyenes szállítás e felett (bruttó HUF, 0 = soha)', 'type' => 'number', 'default' => 25000],
            ],
        ],

        'payments' => [
            'label' => 'Fizetési módok',
            'fields' => [
                'payments.sandbox' => ['label' => 'Teszt (sandbox) mód minden fizetési szolgáltatónál', 'type' => 'bool', 'default' => true],

                'payments.barion.enabled' => ['label' => 'Barion bekapcsolva', 'type' => 'bool', 'default' => false],
                'payments.barion.pos_key' => ['label' => 'Barion POSKey', 'type' => 'secret', 'default' => ''],
                'payments.barion.payee' => ['label' => 'Barion kedvezményezett e-mail (wallet)', 'type' => 'text', 'default' => ''],

                'payments.simplepay.enabled' => ['label' => 'SimplePay bekapcsolva', 'type' => 'bool', 'default' => false],
                'payments.simplepay.merchant' => ['label' => 'SimplePay MERCHANT (HUF)', 'type' => 'text', 'default' => ''],
                'payments.simplepay.secret_key' => ['label' => 'SimplePay SECRET_KEY (HUF)', 'type' => 'secret', 'default' => ''],

                'payments.stripe.enabled' => ['label' => 'Stripe bekapcsolva', 'type' => 'bool', 'default' => false],
                'payments.stripe.publishable_key' => ['label' => 'Stripe publishable key', 'type' => 'text', 'default' => ''],
                'payments.stripe.secret_key' => ['label' => 'Stripe secret key', 'type' => 'secret', 'default' => ''],
                'payments.stripe.webhook_secret' => ['label' => 'Stripe webhook signing secret', 'type' => 'secret', 'default' => ''],

                'payments.revolut.enabled' => ['label' => 'Revolut Business (Merchant API) bekapcsolva', 'type' => 'bool', 'default' => false],
                'payments.revolut.secret_key' => ['label' => 'Revolut Merchant API secret key', 'type' => 'secret', 'default' => ''],
                'payments.revolut.webhook_secret' => ['label' => 'Revolut webhook signing secret', 'type' => 'secret', 'default' => ''],

                'payments.bank_transfer.enabled' => ['label' => 'Banki átutalás (előre utalás)', 'type' => 'bool', 'default' => true],
                'payments.cod.enabled' => ['label' => 'Utánvét', 'type' => 'bool', 'default' => false],
                'payments.cod.fee_gross' => ['label' => 'Utánvét díja (bruttó HUF)', 'type' => 'number', 'default' => 590],
            ],
        ],

        'mail' => [
            'label' => 'E-mail küldés',
            'fields' => [
                'mail.driver' => ['label' => 'Küldési mód', 'type' => 'select', 'default' => 'log', 'options' => [
                    'smtp' => 'SMTP (Laravel mailer)',
                    'phpmailer' => 'Saját PHPMailer (SMTP)',
                    'ses' => 'Amazon SES (AWS)',
                    'http_api' => 'HTTP API (demcsak.hu-féle szolgáltatás – konfigurálható)',
                    'log' => 'Csak naplózás (fejlesztés)',
                ]],
                'mail.from_address' => ['label' => 'Feladó e-mail', 'type' => 'text', 'default' => 'noreply@pooney.com'],
                'mail.from_name' => ['label' => 'Feladó neve', 'type' => 'text', 'default' => 'Pooney'],
                'mail.reply_to' => ['label' => 'Válaszcím', 'type' => 'text', 'default' => 'info@pooney.com'],

                'mail.smtp.host' => ['label' => 'SMTP host', 'type' => 'text', 'default' => ''],
                'mail.smtp.port' => ['label' => 'SMTP port', 'type' => 'number', 'default' => 587],
                'mail.smtp.encryption' => ['label' => 'SMTP titkosítás', 'type' => 'select', 'default' => 'tls', 'options' => ['tls' => 'STARTTLS', 'ssl' => 'SSL/TLS', '' => 'Nincs']],
                'mail.smtp.username' => ['label' => 'SMTP felhasználó', 'type' => 'text', 'default' => ''],
                'mail.smtp.password' => ['label' => 'SMTP jelszó', 'type' => 'secret', 'default' => ''],

                'mail.ses.key' => ['label' => 'AWS access key ID', 'type' => 'text', 'default' => ''],
                'mail.ses.secret' => ['label' => 'AWS secret access key', 'type' => 'secret', 'default' => ''],
                'mail.ses.region' => ['label' => 'AWS régió', 'type' => 'text', 'default' => 'eu-central-1'],

                'mail.http_api.endpoint' => ['label' => 'HTTP API végpont (POST JSON)', 'type' => 'text', 'default' => ''],
                'mail.http_api.token' => ['label' => 'HTTP API token (Bearer)', 'type' => 'secret', 'default' => ''],
                'mail.http_api.payload_template' => ['label' => 'Payload sablon (JSON, {{to}} {{subject}} {{html}} {{from}} {{from_name}})', 'type' => 'textarea',
                    'default' => '{"from":{"email":"{{from}}","name":"{{from_name}}"},"to":[{"email":"{{to}}"}],"subject":"{{subject}}","html":"{{html}}"}'],
            ],
        ],

        'ai' => [
            'label' => 'AI (termék átnevezés, leírás)',
            'fields' => [
                'ai.provider' => ['label' => 'AI szolgáltató', 'type' => 'select', 'default' => 'auto', 'options' => [
                    'auto' => 'Automatikus (Claude, majd OpenAI tartalék)', 'claude' => 'Csak Claude', 'openai' => 'Csak OpenAI',
                ]],
                'ai.anthropic_key' => ['label' => 'Anthropic API key', 'type' => 'secret', 'default' => ''],
                'ai.anthropic_model' => ['label' => 'Claude modell', 'type' => 'text', 'default' => 'claude-sonnet-5-5'],
                'ai.openai_key' => ['label' => 'OpenAI API key', 'type' => 'secret', 'default' => ''],
                'ai.openai_model' => ['label' => 'OpenAI modell', 'type' => 'text', 'default' => 'gpt-5.6-terra'],
                'ai.languages' => ['label' => 'Generált nyelvek (vesszővel)', 'type' => 'text', 'default' => 'hu,en'],
                'ai.brand_voice' => ['label' => 'Márkahang / stílus leírás', 'type' => 'textarea', 'default' => 'Barátságos, közérthető, magyar webáruházi stílus. Ne említsd az AliExpresst, a beszállítót vagy a kínai eredetet.'],
            ],
        ],

        'supplier' => [
            'label' => 'Beszerzés (AliExpress)',
            'fields' => [
                'supplier.auto_order' => ['label' => 'Fizetett rendelés automatikus beszerzése', 'type' => 'bool', 'default' => false],
                'supplier.mode' => ['label' => 'Beszerzés módja', 'type' => 'select', 'default' => 'manual', 'options' => [
                    'manual' => 'Kézi (admin rendeli meg, beírja a rendelésszámot)',
                    'api' => 'AliExpress Dropshipping API (automatikus)',
                ]],
                'supplier.aliexpress.app_key' => ['label' => 'AliExpress Open Platform App Key', 'type' => 'text', 'default' => ''],
                'supplier.aliexpress.app_secret' => ['label' => 'App Secret', 'type' => 'secret', 'default' => ''],
                'supplier.aliexpress.access_token' => ['label' => 'Access token (seller/buyer session)', 'type' => 'secret', 'default' => ''],
                'supplier.aliexpress.endpoint' => ['label' => 'API gateway', 'type' => 'text', 'default' => 'https://api-sg.aliexpress.com/sync'],
                'supplier.aliexpress.ship_to_country' => ['label' => 'Szállítási ország (ISO)', 'type' => 'text', 'default' => 'HU'],
                'supplier.aliexpress.logistics_service' => ['label' => 'Preferált szállítási szolgáltatás kód', 'type' => 'text', 'default' => ''],
                'supplier.max_cost_increase_percent' => ['label' => 'Beszerzési ár max. emelkedése rendeléskor (%) – felette kézi jóváhagyás', 'type' => 'number', 'default' => 10],
                'supplier.legacy_storage_path' => ['label' => 'alidownload storage mappa (import forrás)', 'type' => 'text', 'default' => 'C:\\xampp\\htdocs\\alidownload\\storage'],
                'supplier.max_images' => ['label' => 'Max. termékkép / termék', 'type' => 'number', 'default' => 5],
                'tracking.provider' => ['label' => 'Csomagkövetés forrása', 'type' => 'select', 'default' => 'aliexpress', 'options' => [
                    'aliexpress' => 'AliExpress API', '17track' => '17TRACK API', 'manual' => 'Kézi',
                ]],
                'tracking.17track_key' => ['label' => '17TRACK API key', 'type' => 'secret', 'default' => ''],
            ],
        ],

        'invoicing' => [
            'label' => 'Számlázás',
            'fields' => [
                'invoice.provider' => ['label' => 'Számlázó', 'type' => 'select', 'default' => 'internal', 'options' => [
                    'internal' => 'Belső PDF (csak fejlesztéshez / díjbekérő)',
                    'szamlazzhu' => 'Számlázz.hu (NAV online) – következő lépés',
                    'billingo' => 'Billingo (NAV online) – következő lépés',
                ]],
                'invoice.prefix' => ['label' => 'Számlaszám előtag', 'type' => 'text', 'default' => 'PNY'],
                'invoice.auto_issue_on_paid' => ['label' => 'Számla automatikus kiállítása fizetéskor', 'type' => 'bool', 'default' => true],
                'invoice.szamlazzhu_agent_key' => ['label' => 'Számlázz.hu Számla Agent kulcs', 'type' => 'secret', 'default' => ''],
                'invoice.billingo_api_key' => ['label' => 'Billingo API key', 'type' => 'secret', 'default' => ''],
            ],
        ],

        'automation' => [
            'label' => 'Automatizmusok (cron)',
            'fields' => [
                'automation.payment_reminder_hours' => ['label' => 'Fizetési emlékeztető (óra a rendelés után)', 'type' => 'number', 'default' => 24],
                'automation.cancel_unpaid_after_days' => ['label' => 'Fizetetlen rendelés törlése (nap)', 'type' => 'number', 'default' => 7],
                'automation.review_request_days' => ['label' => 'Termékértékelés kérés (nap a kézbesítés után)', 'type' => 'number', 'default' => 5],
                'automation.survey_days' => ['label' => 'Elégedettségi kérdőív (nap a kézbesítés után)', 'type' => 'number', 'default' => 10],
                'automation.tracking_interval_hours' => ['label' => 'Csomagkövetés frissítése (óránként)', 'type' => 'number', 'default' => 6],
                'automation.notify_tracking_updates' => ['label' => 'Vásárló értesítése követési eseményekről', 'type' => 'bool', 'default' => true],
            ],
        ],
    ],
];
