<?php

namespace App\Enums;

enum OrderStatus: string
{
    case Pending = 'pending';
    case AwaitingPayment = 'awaiting_payment';
    case Paid = 'paid';
    case SupplierOrdered = 'supplier_ordered';
    case Shipped = 'shipped';
    case InTransit = 'in_transit';
    case Delivered = 'delivered';
    case Completed = 'completed';
    case OnHold = 'on_hold';
    case Cancelled = 'cancelled';
    case Refunded = 'refunded';

    public function label(): string
    {
        return match ($this) {
            self::Pending => 'Beérkezett',
            self::AwaitingPayment => 'Fizetésre vár',
            self::Paid => 'Fizetve, feldolgozás alatt',
            self::SupplierOrdered => 'Beszerzés alatt',
            self::Shipped => 'Feladva',
            self::InTransit => 'Szállítás alatt',
            self::Delivered => 'Kézbesítve',
            self::Completed => 'Lezárva',
            self::OnHold => 'Felfüggesztve',
            self::Cancelled => 'Törölve',
            self::Refunded => 'Visszatérítve',
        };
    }

    /** Statuses that trigger an automatic customer e-mail (template key). */
    public function emailTemplate(): ?string
    {
        return match ($this) {
            self::Paid => 'order_paid',
            self::Shipped, self::InTransit => 'order_shipped',
            self::Delivered => 'order_delivered',
            self::Cancelled => 'order_cancelled',
            self::Refunded => 'order_refunded',
            default => null,
        };
    }

    public static function options(): array
    {
        return collect(self::cases())->mapWithKeys(fn (self $s) => [$s->value => $s->label()])->all();
    }
}
