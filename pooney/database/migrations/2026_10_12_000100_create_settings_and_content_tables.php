<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Admin-editable key/value settings (payments, mail, pricing, AI, supplier...).
        // Secret values are stored encrypted with APP_KEY.
        Schema::create('settings', function (Blueprint $table) {
            $table->string('key', 120)->primary();
            $table->text('value')->nullable();
            $table->boolean('is_secret')->default(false);
            $table->timestamps();
        });

        // ÁSZF, adatvédelem, szállítási info, elállás, impresszum... (szerkeszthető)
        Schema::create('pages', function (Blueprint $table) {
            $table->id();
            $table->string('slug', 120)->unique();
            $table->string('title');
            $table->longText('body')->nullable();
            $table->boolean('is_published')->default(true);
            $table->boolean('show_in_footer')->default(true);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamp('version_published_at')->nullable();
            $table->timestamps();
        });

        Schema::create('email_templates', function (Blueprint $table) {
            $table->id();
            $table->string('key', 80)->unique();
            $table->string('name');
            $table->string('group', 40)->default('transactional'); // transactional | marketing | account
            $table->string('subject');
            $table->longText('body');                                 // HTML with {{ placeholders }}
            $table->json('variables')->nullable();                     // documentation for the editor
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('email_logs', function (Blueprint $table) {
            $table->id();
            $table->string('to');
            $table->string('template_key', 80)->nullable()->index();
            $table->string('subject')->nullable();
            $table->string('driver', 30)->nullable();
            $table->string('status', 20)->default('queued'); // queued | sent | failed
            $table->text('error')->nullable();
            $table->nullableMorphs('related');
            $table->timestamp('sent_at')->nullable();
            $table->timestamps();
        });

        Schema::create('newsletter_subscribers', function (Blueprint $table) {
            $table->id();
            $table->string('email')->unique();
            $table->string('name')->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('status', 20)->default('pending'); // pending | subscribed | unsubscribed
            $table->string('token', 64)->unique();
            $table->string('source', 40)->nullable();         // footer | checkout | registration | admin
            $table->timestamp('confirmed_at')->nullable();
            $table->timestamp('unsubscribed_at')->nullable();
            $table->string('unsubscribe_reason')->nullable();
            $table->timestamps();
        });

        // Ajánlatok / hírlevél kampányok
        Schema::create('campaigns', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('subject');
            $table->longText('body');
            $table->string('audience', 30)->default('subscribers'); // subscribers | customers | all_users
            $table->string('status', 20)->default('draft');          // draft | scheduled | sending | sent
            $table->timestamp('scheduled_at')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->unsignedInteger('recipients_count')->default(0);
            $table->timestamps();
        });

        // Kérdőívek ("hogy tetszett az oldal", vásárlás utáni elégedettség...)
        Schema::create('surveys', function (Blueprint $table) {
            $table->id();
            $table->string('slug', 80)->unique();
            $table->string('title');
            $table->text('intro')->nullable();
            $table->json('questions'); // [{key, label, type: rating|text|choice, options: []}]
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('survey_responses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('survey_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedBigInteger('order_id')->nullable()->index();
            $table->string('email')->nullable();
            $table->json('answers');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach (['survey_responses', 'surveys', 'campaigns', 'newsletter_subscribers', 'email_logs', 'email_templates', 'pages', 'settings'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
