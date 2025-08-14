package main

import (
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5" // Лёгкий и быстрый роутер для Go
	"github.com/joho/godotenv" // Для загрузки переменных окружения из .env файла
)

func main() {
	_ = godotenv.Load()

	addr := env("HTTP_ADDR", ":8080")

	r := chi.NewRouter()

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	log.Printf("listening on %s", addr)

	if err := http.ListenAndServe(addr, r); err != nil {
		log.Fatal(err)
	}

}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
