<?php

namespace App\Services\Catalog;

use App\Models\Product;
use App\Models\ProductVariant;
use App\Services\Settings;

/**
 * Supplier cost -> customer price.
 *
 *   cost_huf = (supplier_price [+ supplier_shipping]) * fx_rate * (1 + fx_buffer)
 *   net      = max(cost_huf * (1 + markup), cost_huf + min_margin)
 *   gross    = round(net * (1 + vat))
 *
 * Markup and VAT resolve product -> category -> global setting.
 */
class PriceCalculator
{
    public function __construct(private readonly Settings $settings) {}

    public function markupPercent(Product $product): float
    {
        return (float) ($product->markup_percent ?? $product->category?->markup_percent ?? $this->settings->float('pricing.markup_percent', 85));
    }

    public function vatRate(?Product $product = null): float
    {
        if ($this->settings->get('pricing.vat_mode') === 'aam') {
            return 0.0;
        }

        return (float) ($product?->vat_rate ?? $product?->category?->vat_rate ?? $this->settings->float('pricing.vat_rate', 27));
    }

    public function toHuf(float $amount, string $currency): float
    {
        $rate = match (strtoupper($currency)) {
            'HUF' => 1.0,
            'USD' => $this->settings->float('pricing.usd_huf_rate', 365),
            default => $this->settings->float('pricing.eur_huf_rate', 400),
        };

        return $amount * $rate * (1 + $this->settings->float('pricing.fx_buffer_percent', 3) / 100);
    }

    /** Landed supplier cost in HUF for one unit. */
    public function unitCostHuf(Product $product, ?ProductVariant $variant = null): ?float
    {
        $price = $variant?->supplier_price ?? $product->supplier_price;
        if ($price === null) {
            return null;
        }

        $cost = (float) $price;
        if ($this->settings->bool('pricing.include_supplier_shipping') && ! $product->free_shipping) {
            $cost += (float) $product->supplier_shipping;
        }

        return $this->toHuf($cost, $product->supplier_currency ?: 'EUR');
    }

    /** @return array{net: float, vat_rate: float, gross: float, cost: ?float, margin: ?float} */
    public function quote(Product $product, ?ProductVariant $variant = null): array
    {
        $vat = $this->vatRate($product);
        $cost = $this->unitCostHuf($product, $variant);
        $override = $variant?->price_override_gross ?? $product->price_override_gross;

        if ($override !== null) {
            $gross = (float) $override;
        } elseif ($cost !== null) {
            $net = max($cost * (1 + $this->markupPercent($product) / 100), $cost + $this->settings->float('pricing.min_margin_huf', 0));
            $gross = $this->round($net * (1 + $vat / 100));
        } else {
            $gross = 0.0;
        }

        $net = round($gross / (1 + $vat / 100), 2);

        return [
            'net' => $net,
            'vat_rate' => $vat,
            'gross' => $gross,
            'cost' => $cost !== null ? round($cost, 2) : null,
            'margin' => $cost !== null ? round($net - $cost, 2) : null,
        ];
    }

    public function round(float $gross): float
    {
        return match ((string) $this->settings->get('pricing.rounding', '90')) {
            '10' => ceil($gross / 10) * 10,
            '90' => ceil(($gross + 10) / 100) * 100 - 10,
            '990' => ceil(($gross + 10) / 1000) * 1000 - 10,
            default => round($gross),
        };
    }

    /** Recompute and cache price_gross for a product and its variants. */
    public function refresh(Product $product): Product
    {
        $product->loadMissing('category', 'variants');
        $product->price_gross = $this->quote($product)['gross'] ?: null;
        $product->saveQuietly();

        foreach ($product->variants as $variant) {
            $variant->price_gross = $this->quote($product, $variant)['gross'] ?: null;
            $variant->saveQuietly();
        }

        return $product;
    }
}
