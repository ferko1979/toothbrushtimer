<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Address extends Model
{
    protected $fillable = ['user_id', 'type', 'name', 'company', 'tax_number', 'country', 'zip', 'city', 'line1', 'line2', 'phone', 'is_default'];
    protected $casts = ['is_default' => 'boolean'];

    public function toSnapshot(): array
    {
        return $this->only(['name', 'company', 'tax_number', 'country', 'zip', 'city', 'line1', 'line2', 'phone']);
    }
}
