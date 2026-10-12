<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

#[Fillable(['name', 'email', 'password', 'role', 'phone', 'locale', 'newsletter_opt_in', 'last_login_at'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable implements MustVerifyEmail
{
    /** @use HasFactory<UserFactory> */
    use HasFactory, Notifiable;

    public const ROLES = ['customer' => 'Vásárló', 'order_manager' => 'Rendeléskezelő', 'admin' => 'Adminisztrátor'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'last_login_at' => 'datetime',
            'newsletter_opt_in' => 'boolean',
            'password' => 'hashed',
        ];
    }

    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }

    public function canManageOrders(): bool
    {
        return in_array($this->role, ['admin', 'order_manager'], true);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class)->latest();
    }

    public function addresses(): HasMany
    {
        return $this->hasMany(Address::class);
    }

    public function complaints(): HasMany
    {
        return $this->hasMany(Complaint::class)->latest();
    }

    /** Use our own editable e-mail templates instead of Laravel's default notification. */
    public function sendEmailVerificationNotification(): void
    {
        app(\App\Services\Mail\TemplateMailer::class)->sendVerifyEmail($this);
    }

    public function sendPasswordResetNotification($token): void
    {
        app(\App\Services\Mail\TemplateMailer::class)->sendPasswordReset($this, $token);
    }
}
