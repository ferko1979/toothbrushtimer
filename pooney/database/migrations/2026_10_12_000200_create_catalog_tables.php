<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('parent_id')->nullable()->constrained('categories')->nullOnDelete();
            $table->string('name');
            $table->string('slug')->unique();
            $table->decimal('markup_percent', 6, 2)->nullable(); // overrides global markup
            $table->decimal('vat_rate', 5, 2)->nullable();       // overrides global VAT
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();
        });

        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->string('reference', 32)->unique();           // public MQ-P style random reference
            $table->string('slug')->unique();
            $table->foreignId('category_id')->nullable()->constrained()->nullOnDelete();

            // Public (AI renamed) content
            $table->string('name');
            $table->string('name_en')->nullable();
            $table->string('fantasy_name')->nullable();
            $table->text('short_description')->nullable();
            $table->longText('description')->nullable();
            $table->json('benefits')->nullable();
            $table->json('translations')->nullable();            // additional languages

            // Supplier / sourcing (never shown to customers)
            $table->string('supplier', 30)->default('aliexpress');
            $table->string('source_id', 64)->nullable()->index();
            $table->text('source_url')->nullable();
            $table->string('original_title', 500)->nullable();
            $table->decimal('supplier_price', 12, 2)->nullable();
            $table->string('supplier_currency', 3)->default('EUR');
            $table->decimal('supplier_shipping', 12, 2)->nullable();
            $table->string('ship_from_country', 2)->nullable();
            $table->boolean('is_eu_warehouse')->default(false);
            $table->boolean('free_shipping')->default(false);
            $table->unsignedSmallInteger('delivery_days_min')->nullable();
            $table->unsignedSmallInteger('delivery_days_max')->nullable();
            $table->string('legacy_id', 64)->nullable()->unique();  // id in the alidownload storage
            $table->json('raw')->nullable();                        // last imported supplier payload

            // Pricing
            $table->decimal('markup_percent', 6, 2)->nullable();   // null = category/global
            $table->decimal('vat_rate', 5, 2)->nullable();          // null = category/global
            $table->decimal('price_override_gross', 12, 2)->nullable(); // fixed HUF price if set
            $table->decimal('compare_at_gross', 12, 2)->nullable();
            $table->decimal('price_gross', 12, 2)->nullable();      // cached computed sale price (HUF)

            // Workflow
            $table->string('status', 20)->default('imported')->index(); // imported | screened | approved | published | rejected | archived
            $table->unsignedTinyInteger('screening_score')->nullable();
            $table->json('screening_notes')->nullable();
            $table->timestamp('ai_named_at')->nullable();
            $table->timestamp('supplier_checked_at')->nullable();
            $table->boolean('is_available')->default(true);
            $table->boolean('is_featured')->default(false);
            $table->timestamp('published_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('product_images', function (Blueprint $table) {
            $table->id();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->string('path');            // relative to the public disk
            $table->text('source_url')->nullable();
            $table->string('alt')->nullable();
            $table->unsignedSmallInteger('sort')->default(0);
            $table->timestamps();
        });

        Schema::create('product_variants', function (Blueprint $table) {
            $table->id();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('supplier_sku_id', 128)->nullable();
            $table->json('attributes')->nullable();
            $table->decimal('supplier_price', 12, 2)->nullable();
            $table->decimal('price_override_gross', 12, 2)->nullable();
            $table->decimal('price_gross', 12, 2)->nullable();
            $table->integer('stock')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        // Termék visszajelzés / értékelés
        Schema::create('product_reviews', function (Blueprint $table) {
            $table->id();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedBigInteger('order_id')->nullable()->index();
            $table->string('author_name');
            $table->string('email')->nullable();
            $table->unsignedTinyInteger('rating');
            $table->string('title')->nullable();
            $table->text('body')->nullable();
            $table->boolean('is_verified_purchase')->default(false);
            $table->string('status', 20)->default('pending'); // pending | approved | rejected
            $table->timestamps();
        });

        Schema::create('import_batches', function (Blueprint $table) {
            $table->id();
            $table->string('source', 30)->default('legacy_storage'); // legacy_storage | urls | csv
            $table->string('status', 20)->default('pending');
            $table->unsignedInteger('total')->default(0);
            $table->unsignedInteger('created_count')->default(0);
            $table->unsignedInteger('updated_count')->default(0);
            $table->unsignedInteger('failed_count')->default(0);
            $table->json('log')->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        foreach (['import_batches', 'product_reviews', 'product_variants', 'product_images', 'products', 'categories'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
