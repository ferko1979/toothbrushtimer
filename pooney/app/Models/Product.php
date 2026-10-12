<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

class Product extends Model
{
    use SoftDeletes;

    public const STATUSES = ['imported', 'screened', 'approved', 'published', 'rejected', 'archived'];

    protected $fillable = [
        'reference', 'slug', 'category_id', 'name', 'name_en', 'fantasy_name', 'short_description', 'description',
        'benefits', 'translations', 'supplier', 'source_id', 'source_url', 'original_title', 'supplier_price',
        'supplier_currency', 'supplier_shipping', 'ship_from_country', 'is_eu_warehouse', 'free_shipping',
        'delivery_days_min', 'delivery_days_max', 'legacy_id', 'raw', 'markup_percent', 'vat_rate',
        'price_override_gross', 'compare_at_gross', 'price_gross', 'status', 'screening_score', 'screening_notes',
        'ai_named_at', 'supplier_checked_at', 'is_available', 'is_featured', 'published_at',
    ];

    // Supplier data must never leak into JSON responses / front-end.
    protected $hidden = ['source_id', 'source_url', 'original_title', 'supplier_price', 'supplier_currency', 'supplier_shipping', 'raw', 'markup_percent', 'legacy_id'];

    protected $casts = [
        'benefits' => 'array', 'translations' => 'array', 'raw' => 'array', 'screening_notes' => 'array',
        'is_eu_warehouse' => 'boolean', 'free_shipping' => 'boolean', 'is_available' => 'boolean', 'is_featured' => 'boolean',
        'supplier_price' => 'decimal:2', 'supplier_shipping' => 'decimal:2', 'markup_percent' => 'decimal:2',
        'vat_rate' => 'decimal:2', 'price_override_gross' => 'decimal:2', 'compare_at_gross' => 'decimal:2', 'price_gross' => 'decimal:2',
        'ai_named_at' => 'datetime', 'supplier_checked_at' => 'datetime', 'published_at' => 'datetime',
    ];

    public function getRouteKeyName(): string
    {
        return 'slug';
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    public function images(): HasMany
    {
        return $this->hasMany(ProductImage::class)->orderBy('sort');
    }

    public function variants(): HasMany
    {
        return $this->hasMany(ProductVariant::class);
    }

    public function reviews(): HasMany
    {
        return $this->hasMany(ProductReview::class);
    }

    public function scopePublished($query)
    {
        return $query->where('status', 'published')->where('is_available', true);
    }

    public function coverUrl(): ?string
    {
        $image = $this->images->first();

        return $image ? Storage::disk('public')->url($image->path) : null;
    }

    public function displayName(): string
    {
        return $this->fantasy_name ?: $this->name;
    }
}
