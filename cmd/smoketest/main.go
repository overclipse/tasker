package main
import (
	"log"
	"os"
	"tasker/internal/repo/sqlc"
	"time"
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is empty")
	}
	
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second) 
	defer cancel()   //Контекст с таймаутом если БД зависнет 

	pool, err := pgxpool.New(ctx, dsn) //Создание пула соединений с Postgres
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()  //Гарантированное закрытие после остановки main

	q := sqlc.New(pool) //Готовое соединение к БД
	
	//Шаг 2 Создаем пользователя

	email := "demo+" + time.Now().Format("20060102_150405") + "@example.com" //Для того что бы небыло дубликатов, делаем суфикс во времени
	
	u, err := q.CreateUser(ctx, sqlc.CreateUserParams{
		Email: email,
		PasswordHash: "fake-hash",  //В реальноси тут должен быть bcrypt-хэш
	})
	
	if err != nil {
		log.Printf("CrateUser error: %v", err)
	} else {
		log.Printf("CreateUser ok: id=%d email=%s", u.ID, u.Email)
	}  //И так мы создаем пользователя 
	
	//Шаг 3 Получаем пользователя по email.

	u2, err := q.GetUserByEmail(ctx, email)
	if err != nil {
		log.Fatal("GetUserByEmail error: %v", err)
	}
	
	log.Printf("GetUserByEmail ok: id= %d email=%s", u2.ID, u2.Email)

}