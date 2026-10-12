<?php

use App\Services\Settings;

if (! function_exists('setting')) {
    function setting(string $key, mixed $default = null): mixed
    {
        return app(Settings::class)->get($key, $default);
    }
}

if (! function_exists('huf')) {
    function huf(float|string|null $amount): string
    {
        return number_format((float) $amount, 0, ',', ' ').' Ft';
    }
}
