<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('addresses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('type', 10)->default('shipping'); // shipping | billing
            $table->string('name');
            $table->string('company')->nullable();
            $table->string('tax_number', 40)->nullable();
            $table->string('country', 2)->default('HU');
            $table->string('zip', 12);
            $table->string('city');
            $table->string('line1');
            $table->string('line2')->nullable();
            $table->string('phone', 40)->nullable();
            $table->boolean('is_default')->default(false);
            $table->timestamps();
        });

        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->string('number', 32)->unique();
            $table->string('tracking_token', 64)->unique();   // guest link: /rendeles/{token}
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('email');
            $table->string('phone', 40)->nullable();
            $table->string('customer_name');
            $table->json('billing_address');
            $table->json('shipping_address');

            $table->string('status', 30)->default('pending')->index();
            // pending -> awaiting_payment -> paid -> supplier_ordered -> shipped -> in_transit -> delivered -> completed
            // cancelled | refunded | on_hold
            $table->string('payment_status', 20)->default('unpaid')->index(); // unpaid | pending | paid | failed | refunded
            $table->string('payment_method', 30)->nullable();

            $table->string('currency', 3)->default('HUF');
            $table->decimal('subtotal_net', 12, 2)->default(0);
            $table->decimal('vat_total', 12, 2)->default(0);
            $table->decimal('shipping_gross', 12, 2)->default(0);
            $table->decimal('discount_gross', 12, 2)->default(0);
            $table->decimal('total_gross', 12, 2)->default(0);
            $table->decimal('supplier_cost_total', 12, 2)->nullable();      // internal margin tracking

            $table->text('customer_note')->nullable();
            $table->text('internal_note')->nullable();
            $table->string('locale', 5)->default('hu');
            $table->string('ip', 45)->nullable();
            $table->timestamp('terms_accepted_at')->nullable();
            $table->boolean('newsletter_opt_in')->default(false);

            $table->string('invoice_number', 40)->nullable();
            $table->string('invoice_token', 64)->nullable()->unique();
            $table->string('invoice_path')->nullable();
            $table->string('invoice_provider', 30)->nullable();

            $table->timestamp('placed_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('shipped_at')->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->timestamp('payment_reminder_sent_at')->nullable();
            $table->timestamp('review_request_sent_at')->nullable();
            $table->timestamp('survey_sent_at')->nullable();
            $table->timestamps();
        });

        Schema::create('order_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('product_variant_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name');
            $table->string('variant_name')->nullable();
            $table->string('reference', 32)->nullable();
            $table->unsignedInteger('quantity');
            $table->decimal('vat_rate', 5, 2);
            $table->decimal('unit_net', 12, 2);
            $table->decimal('unit_gross', 12, 2);
            $table->decimal('line_gross', 12, 2);
            $table->decimal('supplier_unit_cost', 12, 2)->nullable();
            $table->string('supplier_currency', 3)->nullable();
            $table->timestamps();
        });

        Schema::create('order_status_histories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->string('from_status', 30)->nullable();
            $table->string('to_status', 30);
            $table->text('note')->nullable();
            $table->boolean('customer_notified')->default(false);
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete(); // admin who changed it (null = system/cron)
            $table->timestamps();
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->string('gateway', 30);                  // barion | simplepay | stripe | revolut | bank_transfer | cod
            $table->string('gateway_reference')->nullable()->index();
            $table->string('status', 20)->default('created'); // created | pending | succeeded | failed | cancelled | refunded
            $table->decimal('amount', 12, 2);
            $table->string('currency', 3);
            $table->text('redirect_url')->nullable();
            $table->json('payload')->nullable();
            $table->timestamp('last_checked_at')->nullable();
            $table->timestamps();
        });

        // Automatic AliExpress (or other supplier) purchase per order
        Schema::create('supplier_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->string('supplier', 30)->default('aliexpress');
            $table->string('mode', 20)->default('manual');          // api | manual
            $table->string('status', 30)->default('queued')->index();
            // queued | placing | placed | manual_required | failed | shipped | delivered | cancelled
            $table->string('supplier_order_id')->nullable()->index();
            $table->decimal('cost', 12, 2)->nullable();
            $table->string('cost_currency', 3)->nullable();
            $table->string('carrier')->nullable();
            $table->string('tracking_number')->nullable()->index();
            $table->text('tracking_url')->nullable();
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->text('last_error')->nullable();
            $table->json('items');                                    // [{order_item_id, source_id, sku_id, qty}]
            $table->json('raw')->nullable();
            $table->timestamp('placed_at')->nullable();
            $table->timestamp('tracking_checked_at')->nullable();
            $table->timestamps();
        });

        Schema::create('shipment_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_order_id')->nullable()->constrained()->nullOnDelete();
            $table->string('status', 40);
            $table->string('description');
            $table->string('location')->nullable();
            $table->timestamp('occurred_at');
            $table->string('hash', 64)->unique();                     // dedupe of tracking events
            $table->timestamp('customer_notified_at')->nullable();
            $table->timestamps();
        });

        // Reklamációk / elállás / visszaküldés
        Schema::create('complaints', function (Blueprint $table) {
            $table->id();
            $table->string('number', 32)->unique();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_item_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('email');
            $table->string('type', 30); // damaged | missing | wrong_item | not_arrived | withdrawal | other
            $table->text('description');
            $table->json('attachments')->nullable();
            $table->string('status', 20)->default('open'); // open | in_progress | waiting_customer | resolved | rejected
            $table->text('resolution')->nullable();
            $table->decimal('refund_amount', 12, 2)->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();
        });

        Schema::create('complaint_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('complaint_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('author', 10); // customer | staff
            $table->text('body');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach (['complaint_messages', 'complaints', 'shipment_events', 'supplier_orders', 'payments', 'order_status_histories', 'order_items', 'orders', 'addresses'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
