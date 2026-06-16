#Start from go base image
FROM golang:1.22.5 AS base

#set the working directory inside container
WORKDIR /app

#copy the go.mod and go.sum inside working directtory
COPY go.mod ./

#Download all the go dependencies
RUN go mod download

#copy the sourcec code to working directory
COPY . .

#Build the go application
RUN go build -o main .

#############################
#Reduce the build with multi-stage  build 
# we will use distroless  image to run the application
FROM gcr.io/distroless/base

#Copy the binary from previous stage
COPY --from=base /app/main .

#copy the static files from previous stage
COPY --from=base /app/static ./static

#Expose the port on which appliication will run
EXPOSE  8080

#Command to run the application
CMD [ "./main" ]