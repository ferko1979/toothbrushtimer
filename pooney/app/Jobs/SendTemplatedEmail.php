<?php

namespace App\Jobs;

use App\Models\EmailLog;
use App\Services\Mail\TemplateMailer;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

class SendTemplatedEmail implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public array $backoff = [60, 300, 900];

    public function __construct(
        public int $logId,
        public string $templateKey,
        public string $to,
        public array $vars,
    ) {}

    public function handle(TemplateMailer $mailer): void
    {
        $mailer->deliver($this->templateKey, $this->to, $this->vars, EmailLog::find($this->logId));
    }
}
