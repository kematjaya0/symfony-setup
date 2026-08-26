import Link from 'next/link';

export default function HomePage() {
    return (
        <main className="shell">
            <section className="card">
                <h1>Welcome</h1>
                <p className="muted">
                    Tokens stay in HttpOnly cookies. Browser requests only this
                    Next.js app.
                </p>
                <div className="row">
                    <Link className="button" href="/login">
                        Login
                    </Link>
                    <Link className="button secondary" href="/register">
                        Register
                    </Link>
                </div>
            </section>
        </main>
    );
}
