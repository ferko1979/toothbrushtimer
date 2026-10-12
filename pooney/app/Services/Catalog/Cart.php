<?php

namespace App\Services\Catalog;

use App\Models\Product;
use App\Models\ProductVariant;
use App\Services\Settings;
use Illuminate\Support\Collection;

/** Session based cart: [lineKey => [product_id, variant_id, qty]]. */
class Cart
{
    private const KEY = 'cart.lines';

    public function __construct(private readonly PriceCalculator $prices, private readonly Settings $settings) {}

    public function add(Product $product, ?ProductVariant $variant, int $qty = 1): void
    {
        $lines = session(self::KEY, []);
        $key = $product->id.':'.($variant?->id ?? 0);
        $lines[$key] = [
            'product_id' => $product->id,
            'variant_id' => $variant?->id,
            'qty' => min(99, ($lines[$key]['qty'] ?? 0) + max(1, $qty)),
        ];
        session([self::KEY => $lines]);
    }

    public function update(string $key, int $qty): void
    {
        $lines = session(self::KEY, []);
        if ($qty <= 0) {
            unset($lines[$key]);
        } elseif (isset($lines[$key])) {
            $lines[$key]['qty'] = min(99, $qty);
        }
        session([self::KEY => $lines]);
    }

    public function clear(): void
    {
        session()->forget(self::KEY);
    }

    public function count(): int
    {
        return (int) collect(session(self::KEY, []))->sum('qty');
    }

    /** Resolved lines with current prices (prices are never trusted from the session). */
    public function lines(): Collection
    {
        $raw = collect(session(self::KEY, []));
        $products = Product::published()->with('category', 'images')->whereIn('id', $raw->pluck('product_id'))->get()->keyBy('id');
        $variants = ProductVariant::whereIn('id', $raw->pluck('variant_id')->filter())->get()->keyBy('id');

        return $raw->map(function (array $line, string $key) use ($products, $variants) {
            $product = $products->get($line['product_id']);
            if (! $product) {
                return null;
            }
            $variant = $line['variant_id'] ? $variants->get($line['variant_id']) : null;
            $quote = $this->prices->quote($product, $variant);

            return (object) [
                'key' => $key,
                'product' => $product,
                'variant' => $variant,
                'qty' => $line['qty'],
                'unit_gross' => $quote['gross'],
                'unit_net' => $quote['net'],
                'vat_rate' => $quote['vat_rate'],
                'unit_cost' => $quote['cost'],
                'line_gross' => $quote['gross'] * $line['qty'],
            ];
        })->filter()->values();
    }

    public function totals(?string $paymentMethod = null): array
    {
        $lines = $this->lines();
        $itemsGross = $lines->sum('line_gross');
        $itemsNet = $lines->sum(fn ($l) => $l->unit_net * $l->qty);

        $freeAbove = $this->settings->float('shipping.free_above_gross');
        $shipping = ($freeAbove > 0 && $itemsGross >= $freeAbove) || $lines->isEmpty() ? 0.0 : $this->settings->float('shipping.fee_gross');
        if ($paymentMethod === 'cod') {
            $shipping += $this->settings->float('payments.cod.fee_gross');
        }

        $shippingVat = $this->prices->vatRate();
        $shippingNet = round($shipping / (1 + $shippingVat / 100), 2);

        return [
            'items_gross' => $itemsGross,
            'shipping_gross' => $shipping,
            'subtotal_net' => round($itemsNet + $shippingNet, 2),
            'vat_total' => round($itemsGross + $shipping - $itemsNet - $shippingNet, 2),
            'total_gross' => $itemsGross + $shipping,
        ];
    }
}
