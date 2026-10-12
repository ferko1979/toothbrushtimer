<?php

namespace App\Services;

use App\Models\Setting;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Schema;
use Throwable;

/**
 * Admin-editable settings backed by the `settings` table, with defaults
 * from config/pooney.php. Secrets are encrypted at rest.
 */
class Settings
{
    private const CACHE_KEY = 'pooney.settings';

    private ?array $values = null;

    public function get(string $key, mixed $default = null): mixed
    {
        $values = $this->all();

        if (array_key_exists($key, $values)) {
            return $values[$key];
        }

        return $this->definition($key)['default'] ?? $default;
    }

    public function bool(string $key): bool
    {
        return filter_var($this->get($key), FILTER_VALIDATE_BOOLEAN);
    }

    public function float(string $key, float $default = 0.0): float
    {
        $value = $this->get($key, $default);

        return is_numeric($value) ? (float) $value : $default;
    }

    public function set(string $key, mixed $value): void
    {
        $secret = ($this->definition($key)['type'] ?? null) === 'secret';
        $stored = is_array($value) ? json_encode($value) : (string) $value;

        Setting::updateOrCreate(['key' => $key], [
            'value' => $secret && $stored !== '' ? Crypt::encryptString($stored) : $stored,
            'is_secret' => $secret,
        ]);

        $this->flush();
    }

    /** @return array<string, mixed> decrypted key => value map */
    public function all(): array
    {
        if ($this->values !== null) {
            return $this->values;
        }

        try {
            if (! Schema::hasTable('settings')) {
                return $this->values = [];
            }
        } catch (Throwable) {
            return $this->values = [];
        }

        $rows = Cache::rememberForever(self::CACHE_KEY, fn () => Setting::all(['key', 'value', 'is_secret'])->toArray());

        $values = [];
        foreach ($rows as $row) {
            $value = $row['value'];
            if ($row['is_secret'] && $value !== null && $value !== '') {
                try {
                    $value = Crypt::decryptString($value);
                } catch (Throwable) {
                    $value = null; // APP_KEY changed – secret must be re-entered
                }
            }
            $values[$row['key']] = $value;
        }

        return $this->values = $values;
    }

    public function definition(string $key): ?array
    {
        foreach (config('pooney.settings', []) as $group) {
            if (isset($group['fields'][$key])) {
                return $group['fields'][$key];
            }
        }

        return null;
    }

    public function groups(): array
    {
        return config('pooney.settings', []);
    }

    public function flush(): void
    {
        Cache::forget(self::CACHE_KEY);
        $this->values = null;
    }

    public function isFilled(string ...$keys): bool
    {
        return Arr::every($keys, fn ($k) => filled($this->get($k)));
    }
}
