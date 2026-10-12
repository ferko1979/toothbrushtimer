<?php

namespace App\Services\Mail;

/**
 * Renders admin-edited templates. Placeholders: {{ name }} is HTML escaped,
 * {!! name !!} is inserted raw (only for values we generate, e.g. item tables / buttons).
 */
class TemplateRenderer
{
    public function render(string $template, array $vars): string
    {
        $template = preg_replace_callback('/\{!!\s*([a-z0-9_.]+)\s*!!\}/i', fn ($m) => (string) data_get($vars, $m[1], ''), $template);

        return preg_replace_callback('/\{\{\s*([a-z0-9_.]+)\s*\}\}/i', fn ($m) => e((string) data_get($vars, $m[1], '')), $template);
    }

    public function button(string $url, string $label): string
    {
        return sprintf(
            '<p style="margin:24px 0"><a href="%s" style="background:#ff6b35;color:#fff;padding:12px 22px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">%s</a></p>',
            e($url), e($label)
        );
    }
}
