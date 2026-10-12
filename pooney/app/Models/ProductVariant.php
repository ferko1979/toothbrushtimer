<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProductVariant extends Model
{
    protected $fillable = ['product_id', 'name', 'supplier_sku_id', 'attributes', 'supplier_price', 'price_override_gross', 'price_gross', 'stock', 'is_active'];
    protected $hidden = ['supplier_sku_id', 'supplier_price'];
    protected $casts = ['attributes' => 'array', 'is_active' => 'boolean', 'supplier_price' => 'decimal:2', 'price_override_gross' => 'decimal:2', 'price_gross' => 'decimal:2'];

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
