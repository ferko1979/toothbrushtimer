<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class OrderItem extends Model
{
    protected $fillable = ['order_id', 'product_id', 'product_variant_id', 'name', 'variant_name', 'reference', 'quantity', 'vat_rate', 'unit_net', 'unit_gross', 'line_gross', 'supplier_unit_cost', 'supplier_currency'];
    protected $casts = ['vat_rate' => 'decimal:2', 'unit_net' => 'decimal:2', 'unit_gross' => 'decimal:2', 'line_gross' => 'decimal:2', 'supplier_unit_cost' => 'decimal:2'];

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class)->withTrashed();
    }

    public function variant(): BelongsTo
    {
        return $this->belongsTo(ProductVariant::class, 'product_variant_id');
    }
}
